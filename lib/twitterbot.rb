# -*- coding: utf-8 -*-
$:.unshift File.dirname(__FILE__)
require 'rubygems'
require 'time'
require 'MeCab'
require 'enumerator' # each_consを利用するため必要
require 'open-uri'
require 'kconv'
require 'oauth'
require 'net/https'
require "json/pure"
require 'yaml'
require 'fileutils'
require 'pp'
require 'optparse'
require 'twitter'
require "thread"

require_relative "twitterbot/database"
require_relative "twitterbot/function"
require_relative "twitterbot/extensions"
require_relative "sandbox"


def logs(msg)
  puts msg + " - " + Time.now.to_s
end

#
# TwitterBot
#

class TwitterBot

  attr_accessor \
    :config, :name, 
    :debug, 
    :config_file,
    :database, :function,
    :CONSUMER_KEY, :CONSUMER_SECRET, :OAUTH_TOEKN, :OAUTH_TOEKN_SECRET,
    :consumer, :token

  BaseDir = Dir::getwd + '/'

  def initialize(path = BaseDir + "config.yaml")
    @config_file = path
    @debug = false
    load_config
  end

  def load_config
    open(@config_file) do |io|
      @config = YAML.load(io)
    end


    # config
    @name = @config['name']
    @files = {
      :db   => BaseDir + @config['files']['db'],
      :cer  => BaseDir + @config['files']['cer']
    }

    @CONSUMER_KEY       = @config['oauth']['ConsumerKey']
    @CONSUMER_SECRET    = @config['oauth']['ConsumerSecret']
    @OAUTH_TOEKN        = @config['oauth']['OauthToken']
    @OAUTH_TOEKN_SECRET = @config['oauth']['OauthTokenSecret']

    @consumer = OAuth::Consumer.new(
      @CONSUMER_KEY,
      @CONSUMER_SECRET,
      :site => 'http://twitter.com'
    )

    @token = OAuth::AccessToken.new(
      @consumer,
      @OAUTH_TOEKN,
      @OAUTH_TOEKN_SECRET
    )

    @_users = Hash.new

    Twitter.configure do |configer|
      configer.consumer_key       = @CONSUMER_KEY      
      configer.consumer_secret    = @CONSUMER_SECRET   
      configer.oauth_token        = @OAUTH_TOEKN
      configer.oauth_token_secret = @OAUTH_TOEKN_SECRET
    end

    # 計算機能のエイリアスの正規表現のパターンを生成
    unless @config['Function']['calculate']['alias_pattern']
      @config['Function']['calculate']['alias_pattern'] = @config['Function']['calculate']['alias'].keys.join('|')
    end

    # 内部クラスのインスタンスを初期化
    @function = Function.new(@config['Function'])
    @database = DataBase.new(@files[:db])

  end

  def post(text, in_reply_to = false, in_reply_to_status_id = nil, time = false, try=10)

    text = "@#{in_reply_to} #{text}" if in_reply_to
    text += " - " + Time.now.to_s if time

    if @debug
      logs "\tdebug>>#{text}"
    else
      (1..try).each do |i|
        # 140文字の制限をチェック
        text = text[0..137] + "(略" if text.length > 140

        begin
          if in_reply_to_status_id
            Twitter.update(text, {:in_reply_to_status_id => in_reply_to_status_id})
          else
            Twitter.update(text)
          end
        rescue Timeout::Error, StandardError, Net::HTTPServerException
          logs "#error: 投稿エラー発生! #{i}回目 [#{text}]"
          text += '　'
          if text.length > 140 || i>=try
            logs "#error: 投稿できまでんでした!!"
            break
          end
        else
          break
        end
      end
      logs "\t>>#{text}"
    end

  end

  def favorite(status)
    id = status['id']
    if @debug
      logs "\tFAV(debug)>>id:#{id}"
    elsif !status['favourited']
      logs "\tFAV>>id:#{id}"
      Twitter.favorite(id)
      status['favourited'] = true
    end
  end

  def retweet(status)
    id = status['id']
    if @debug
      logs "\tRT(debug)>>id:#{id}"
    elsif !status['retweeted']
      logs "\tRT>>id:#{id}"
      Twitter.retweet(id)
      status['retweeted'] = true
    end
  end

  def connect
    i = 0
    while i < 30 do
      begin
        # http://dev.twitter.com/pages/user_streams
        uri = URI.parse('https://userstream.twitter.com/2/user.json')

        # userstreamにはSSLでアクセスする
        https = Net::HTTP.new(uri.host, uri.port)
        https.use_ssl = true
        https.verify_mode = OpenSSL::SSL::VERIFY_PEER
        https.verify_depth = 5
        # 接続先サーバのルートCA証明書をダウンロードしてきて指定
        https.ca_file = @files[:cer]

        https.start do |https|
          req = Net::HTTP::Get.new(uri.request_uri)
          req.oauth!(https, @consumer, @token)

          https.request(req) do |res|
            res.read_body do |chunk|
              # chunked = falseなら例外を発生
              raise 'Response is not chunked' unless res.chunked?

              # JSONのパースに失敗したらスキップして次へ
              status = JSON.parse(chunk) rescue next

              # textパラメータを含まないものはスキップして次へ
              next unless status['text']
              if i > 0
                logs "UserStreamAPIに再接続しました。"
                i = 0
              end
              yield status
            end
          end
        end

        # http://d.hatena.ne.jp/aquarla/20101020/1287540883
        # Timeout::Errorも明示的に捕捉する必要あるらしい。
        # 現状だと、あらゆる例外をキャッチしてしまう。
      rescue Timeout::Error , StandardError => e
        i += 1
        logs "#error: #{$!}"
        logs "\t" + e.backtrace.join("\n")
        sleep_time = (i > 10) ? 5*i : 10
        logs "#{sleep_time}秒後に再接続します。(#{i}回目)"
        sleep(sleep_time)
      end
    end
    logs "#error: Twitterに接続できないため、connectを終了します。"
  end

  #
  # Users[key] の要素を、name から id に変換して返す
  #
  def users(key)
    return @_users[key] if @_users[key]
    @_users[key] = users_core(key)
  end

  def users_core(key)
    result = Array.new
    temp = @config['Users'][key]
    return result unless temp
    temp.each do |val|
      case val.class.to_s
      when "Fixnum"
        result.push val
      when "String"
        begin
          result.push Twitter.user(val).id
        rescue
          logs "#error: Not found such a user[#{val}]"
        end
      when "NilClass"
        #
      else
        raise "to_id"
      end
    end
    return result
  end


  #
  # 文章からマルコフ連鎖のデータを学習する
  #
  def learn(text)

    mecab = MeCab::Tagger.new('-O wakati') 
    node =  mecab.parseToNode(text + " EOS")
    surfaces = Array.new# 分解した単語のリスト
    features = Array.new# 分解した単語の品詞のリスト

    while node do
      surfaces.push(node.surface.toutf8)
      features.push(node.feature.toutf8)
      node = node.next
    end

    @database.open do |db|
      surfaces.each_cons(3) do |a| 
        hash = {:head => a[0], :body => a[1], :tail => a[2]}
        sql = "insert into markov values (:id, :head, :body, :tail)"
        db.execute(sql, hash)
      end
    end

  end

  #
  # keywordを起点にして、マルコフ連鎖で文章を生成する
  #
  def talk(keyword)
    start = Time.now  

    logs "#begin: talk"

    raise "keyword is nil!" if !keyword | keyword.empty?

    text = t1 = t2 = ""

    @database.open do |db|
      for i in 1 .. 5
        list = Array.new
        db.execute("select body from markov where head = '#{keyword.escape_for_sql}'") do |body|
          list.push(body[0].to_s)
        end

        if list.size == 0
          # マルコフ辞書にない単語だったら、nilを返して終了
          logs "#error: Not found in markov table"
          return nil
        end

        t1 = keyword
        t2 = list.sample
        text = t1.eappend t2

        loop do
          list = Array.new
          db.execute("select body, tail from markov where head = '#{t1.escape_for_sql}' and body = '#{t2.escape_for_sql}'") do |body, tail|
            list.push({:body => body.to_s, :tail => tail.to_s})
          end

          break if list.size == 0

          hash = list.sample# 乱数で次の文節を決定する
          t1 = hash[:body]
          t2 = hash[:tail]
          text = text.eappend hash[:tail]
          break if hash[:tail] == "EOS"
        end

        logs "試行回数:#{i}"
        break if text.length <= 100
        return nil if i == 5
      end
    end

    logs "生成時間:#{(Time.now - start).to_s}秒"
    return text.gobi

  end

  #
  # 与えられたNodeが文末なのかを判断する
  #
  def fin?(node)
    return true unless node.next.surface
    return true if node.next.surface.to_s.toutf8 =~ /(EOS| |　|!|！|[.]|。)/
      return false
  end

  #
  # 語尾を変化させる
  #
  def gobi(text)

    # mecabで形態素解析して、 参照テーブルを作る
    mecab = MeCab::Tagger.new('-O wakati') 
    node =  mecab.parseToNode(text)

    buf = ""

    while node do
      feature = node.feature.to_s.toutf8
      surface = node.surface.to_s.toutf8

      if feature =~ /基本形/ && surface != '基本形' && fin?(node)
        buf += surface + 'のだ'
      elsif feature =~ /名詞/ && surface != '名詞' && fin?(node)
        buf += surface + 'なのだ'
      elsif feature == '助詞,接続助詞,*,*,か,か,*'
        buf += surface + 'なのだ'
      elsif feature == '助詞,終助詞,*,*,か,か,*'
        buf += surface + 'なのだ'
      else
        buf = buf.eappend surface
      end

      node = node.next
    end

    buf.gsub("だのだ", "なのだ").gsub("のだよ", "のだ").gsub(/EOS$/,"").gsub(/EOS $/,"").
      gsub(/なのだ [.,]/, "").gsub("なのだ.なのだ", "なのだ").gsub(/(俺|私|わたし|おら)/, "僕").
      gsub('卒', "´").gsub('& gt;', '>').gsub('& lt;', '<').gsub("しました","したのだ").
      gsub(/(「|」|『|』)/, " ")
  end 

end
