# -*- coding: utf-8 -*-
$:.unshift File.dirname(__FILE__)
require 'rubygems'
require 'time'
require "MeCab"
require 'enumerator' # each_consを利用するため必要
require 'open-uri'
require 'kconv'
#require 'oauth'
#require 'net/https'
#require 'json/pure'
require 'yaml'
require 'fileutils'
require 'pp'
require 'optparse'
require 'twitter'
require 'tweetstream'
require 'thread'

require_relative "twitterbot/database"
require_relative "twitterbot/function"
require_relative "twitterbot/extensions"
require_relative "twitterbot/users"
require_relative "sandbox"

def logs(text)
  time = Time.now.strftime("%y.%m.%d-%H:%M:%S")
  puts "#{time} #{text}"
  time
end

#
# TwitterBot
#

class TwitterBot

  attr_accessor \
    :config, :name, 
    :debug, 
    :config_file,
    :users, :coop, :client, :function, :database,
    :CONSUMER_KEY, :CONSUMER_SECRET, :OAUTH_TOEKN, :OAUTH_TOEKN_SECRET

  BaseDir = Dir::getwd + '/'

  def initialize(debug = false, response = false, db = true, config_file = BaseDir + "config.yaml")
    @config_file = config_file
    @debug = debug
    @mecab = MeCab::Tagger.new('-O wakati')
    load_config(response, db)
  end

  def load_config(response, db)

    open(@config_file) do |io|
      @config = YAML.load(io)
    end

    @name = @debug ? @config['name_debug'] : @config['name']

    @files = {
      :db    => BaseDir + @config['files']['db'],
      :cer   => BaseDir + @config['files']['cer'],
      :users => BaseDir + @config['files']['users'],
      :coop  => BaseDir + @config['files']['coop']
    }

    oauth = @debug ? 'oauth_debug' : 'oauth'
    @CONSUMER_KEY       = @config[oauth]['ConsumerKey']
    @CONSUMER_SECRET    = @config[oauth]['ConsumerSecret']
    @OAUTH_TOEKN        = @config[oauth]['OauthToken']
    @OAUTH_TOEKN_SECRET = @config[oauth]['OauthTokenSecret']

    Twitter.configure do |config|
      config.consumer_key       = @CONSUMER_KEY      
      config.consumer_secret    = @CONSUMER_SECRET   
      config.oauth_token        = @OAUTH_TOEKN
      config.oauth_token_secret = @OAUTH_TOEKN_SECRET
    end

    if response
      TweetStream.configure do |config|
        config.consumer_key       = @CONSUMER_KEY      
        config.consumer_secret    = @CONSUMER_SECRET   
        config.oauth_token        = @OAUTH_TOEKN
        config.oauth_token_secret = @OAUTH_TOEKN_SECRET
        config.auth_method        = :oauth
      end
    end

    # 内部クラスのインスタンスを初期化
    if response
      @client = TweetStream::Client.new
      @users = Users.new(@files[:users])
    end
    if db
      @database = DataBase.new(@files[:db])
    end
    @function = Function.new(@config['Function'])
    @coop = Users.new(@files[:coop])

  end

  def post(text, in_reply_to = false, in_reply_to_status_id = nil, time = false, try=1)

    text = "@#{in_reply_to} #{text}" if in_reply_to
    text += " - " + Time.now.to_s if time

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
        logs "#error: 投稿エラー発生! #{i}回目 [#{text}] #{$!}"
        text += '　'
        if i>=try
          logs "#error: 投稿できまでんでした!!"
          break
        end
      else
        break
      end
    end
    logs "\t>>#{text}"

  end

  # 140文字を超えるポストをする。
  def post2(text, in_reply_to = false, in_reply_to_status_id = nil, time = false, try=1, count = 3)

    return if count == 0

    text = "@#{in_reply_to} #{text}" if in_reply_to
    text += " - " + Time.now.to_s if time

    (1..try).each do |i|
      begin
        if text.length <= 140
          if in_reply_to_status_id
            Twitter.update(text, {:in_reply_to_status_id => in_reply_to_status_id})
          else
            Twitter.update(text)
          end
          logs "\t>>#{text}"
        else
          t1, t2 = text.take_lines_at_length(140)
          if count == 1 && !t2.empty?
            if t1.length <= 136
              t1 += "(略"
            else
              t1 = t1[0..137] + "(略" 
            end
          end
          if in_reply_to_status_id
            Twitter.update(t1, {:in_reply_to_status_id => in_reply_to_status_id})
          else
            Twitter.update(t1)
          end
          logs "\t>>#{t1}"
          post2(t2, in_reply_to, in_reply_to_status_id, time, try, count - 1)
        end
      rescue Timeout::Error, StandardError, Net::HTTPServerException
        logs "#error: 投稿エラー発生! #{i}回目 [#{text}] #{$!}"
        text += '　'
        if i>=try
          logs "#error: 投稿できまでんでした!!"
          break
        end
      else
        break
      end
    end
  end


  def favorite(status)
    if status.retweeted_status
      favorite(status.retweeted_status)
      return
    end

    if !status.favourited
      logs "\tFAV>>id:#{status.id}"
      Twitter.favorite(status.id) rescue logs "#error: #{$!}"
    end
  end

  def retweet(status)
    if status.retweeted_status
      retweet(status.retweeted_status)
      return
    end

    if !status.retweeted
      logs "\tRT>>id:#{status.id}"
      Twitter.retweet(status.id) rescue logs "#error: #{$!}"
    end
  end

  #
  # 文章からマルコフ連鎖のデータを学習する
  #
  def learn(text)

    node =  @mecab.parseToNode(text + " EOS")
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
    return gobi(text)

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
    node =  @mecab.parseToNode(text)

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
      gsub('(卒・ω・｀)', "(´・ω・｀)").gsub('& gt;', '>').gsub('& lt;', '<').gsub("しました","したのだ").
      gsub(/(「|」|『|』)/, " ")
  end 

end
