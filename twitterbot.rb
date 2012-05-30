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
require 'net/http'
require "json/pure"
require 'yaml'
require 'sqlite3'
require 'fileutils'
require 'pp'
require 'optparse'
require 'twitter'
require "rexml/document"
include REXML


def logs(msg)
	puts msg + " - " + Time.now.to_s
end

#
#	TwitterBot
#

class TwitterBot

	attr_accessor \
		:config, :name, 
		:debug, 
		:config_file,
		:CONSUMER_KEY, :CONSUMER_SECRET, :OAUTH_TOEKN, :OAUTH_TOEKN_SECRET,
		:consumer, :token

	RootDir = File.dirname(__FILE__) + '/'

	def initialize(path = RootDir + "config.yaml")
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
			:db		=> RootDir + @config['files']['db'],
			:cer	=> RootDir + @config['files']['cer']
		}

		@CONSUMER_KEY				= @config['oauth']['ConsumerKey']
		@CONSUMER_SECRET		= @config['oauth']['ConsumerSecret']
		@OAUTH_TOEKN				= @config['oauth']['OauthToken']
		@OAUTH_TOEKN_SECRET	= @config['oauth']['OauthTokenSecret']

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

		Twitter.configure do |configer|
			configer.consumer_key				= @CONSUMER_KEY			 
			configer.consumer_secret		= @CONSUMER_SECRET	 
			configer.oauth_token				= @OAUTH_TOEKN
			configer.oauth_token_secret	= @OAUTH_TOEKN_SECRET
		end

	end

	def post(text, in_reply_to = false, in_reply_to_status_id = nil, time = false)

		text = "@#{in_reply_to} #{text}" if in_reply_to
		text += " - " + Time.now.to_s if time

		if @debug
			logs "\tdebug>>#{text}"
		else
			begin
				if in_reply_to_status_id
					@token.post('/statuses/update.json', :status => text, :in_reply_to_status_id => in_reply_to_status_id)
				else
					@token.post('/statuses/update.json', :status => text)
				end
			rescue Timeout::Error, StandardError
				logs "#error: 投稿エラー発生! [#{text}]"
			ensure
				logs "\t>>#{text}"
			end
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

				#	http://d.hatena.ne.jp/aquarla/20101020/1287540883
				#	Timeout::Errorも明示的に捕捉する必要あるらしい。
				#	現状だと、あらゆる例外をキャッチしてしまう。
			rescue Timeout::Error, StandardError
				i += 1
				logs "#error: #{$!}"
				sleep_time = (i > 10) ? 5*i : 10
				logs "#{sleep_time}秒後に再接続します。(#{i}回目)"
				sleep(sleep_time)
			end
		end
		logs "#error: Twitterに接続できないため、connectを終了します。"
	end

	#
	#	Users[key] の要素を、name から id に変換して返す
	#

	def users(key)
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
	#	SQLite3関連
	#

	def limit_database(db, table, max = 100000)
		db.execute("select count(*) from #{table}") do |row|
			if row[0] > max
				db.execute("select min(id) from #{table}") do |min|
					db.execute("delete from #{table} where id < #{row[0]-max+min[0]}")
				end
			end
		end
	end

	def open_database
		db = SQLite3::Database.new(@files[:db])
		db.busy_timeout(100000)
		begin
			db.execute("create table markov (id integer primary key, head text, body text, tail text)")
			db.execute("create table stock (id integer primary key, head text)")
			db.execute("create index head on markov(head)")
			db.execute("create index head_and_body on markov(head,body)")
			db.execute("create index stock_head on stock(head)")
		rescue SQLite3::SQLException
			#logs "既にテーブルがあるようです"
		else
			logs "テーブルを新規作成しました。"
		end
		yield db
		begin
			limit_database(db, "markov", 1000000)
			limit_database(db, "stock", 30)
		rescue SQLite3::BusyException
			logs "SQLite3::BusyException"
		end
		db.close
	end

	#
	#	文章から学習する
	#

	def learn(text)

		mecab = MeCab::Tagger.new('-O wakati') 
		node =  mecab.parseToNode(text + " EOS")
		surfaces = Array.new#	分解した単語のリスト
		features = Array.new#	分解した単語の品詞のリスト

		while node do
			surfaces.push(node.surface.toutf8)
			features.push(node.feature.toutf8)
			node = node.next
		end

		open_database do |db|
			surfaces.each_cons(3) do |a| 
				hash = {:head => a[0], :body => a[1], :tail => a[2]}
				sql = "insert into markov values (:id, :head, :body, :tail)"
				db.execute(sql, hash)
			end
		end

	end

	#
	#	ある単語を起点にして、マルコフ連鎖で文章を生成する
	#

	def generate_phrase(keyword)
		start = Time.now	

		logs "#begin: generate_phrase"

		raise "keyword is nil!" if !keyword | keyword.empty?

		text = t1 = t2 = ""

		open_database do |db|
			for i in 1 .. 5
				list = Array.new
				db.execute("select body from markov where head = '#{keyword.escape}'") do |body|
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
					db.execute("select body, tail from markov where head = '#{t1.escape}' and body = '#{t2.escape}'") do |body, tail|
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
	#	天気予報機能
	#

	def weather(day=nil)
		# dayが指定されていなければ設定する
		day = Time.now.hour <= 15 ? "today" : "tomorrow" unless day

		# 英語=>日本語の変換
		hash = {"today" => "今日", "tomorrow" => "明日", "dayaftertomorrow" => "明後日"}

		begin
			uri = URI("http://weather.livedoor.com/forecast/webservice/rest/v1?city=55&day=#{day}")
			xml = Net::HTTP.get(uri)
			doc = Document.new(xml)
			celsius = doc.elements['/lwws/temperature/max/celsius'].get_text
			text = "#{hash[day]}のつくばの天気は、#{doc.elements['/lwws/telop'].get_text}なのだ。"
			text +=  "最高#{celsius}℃なのだ。http://goo.gl/IPAuV" if celsius
		rescue
			return nil
		end
		return text
	end

	#
	#	keywords と stock を取得/追加
	#

	def get_keywords
		list = Array.new
		open_database do |db|
			db.execute("select body from markov where head = ''") do |body|
				list.push body[0]
			end
		end
		return list
	end

	def get_stock
		list = Array.new
		open_database do |db|
			db.execute("select head from stock") do |hash|
				list.push hash[0]
			end
		end
		return list
	end

	def add_stock(keyword)
		open_database do |db|
			hash = {:head => keyword}
			sql = "insert into stock values (:id, :head)"
			db.execute(sql, hash)
		end
	end

end



#
#	String拡張
#

class String

	#
	#	英単語の場合、スペースをはさんで結合
	#

	def eappend(text)
		if text =~ /^\w+$/ && self != ''
			return "#{self} #{text}"
		else
			return "#{self}#{text}"
		end
	end

	#
	# テキストから余分な文字を取り除く
	#

	def filter
		# エンコードをUTF-8 にして、改行とURLや#ハッシュダグや@メンションは消す
		self.toutf8.gsub(/(\n|https?:\S+|from https?:\S+|#\w+|#|@\S+|^RT|なのだ|のだ)/, "")
	end


	#
	#	与えられたNodeが文末なのかを判断する
	#

	def fin?(node)
		return true unless node.next.surface
		return true if node.next.surface.to_s.toutf8 =~ /(EOS| |　|!|！|[.]|。)/
			return false
	end

	#
	#	語尾を変化させる
	#

	def gobi

		# mecabで形態素解析して、 参照テーブルを作る
		mecab = MeCab::Tagger.new('-O wakati') 
		node =  mecab.parseToNode(self)

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

	#
	#	テキストが指定した配列の要素のどれかと一致するならtrueを返す
	#

	def in_hash?(hash)
		hash.each do |item|
			return true if item == self
		end
		return false
	end

	#
	#	テキストにテーブル()の要素が含まれていたなら、そのテーブルのペアの要素をランダムに返す
	#

	def search_table(table)
		table.each do |set|
			set[0].each do |word|
				if self.index(word)
					return set[1].sample
				end
			end
		end
		return nil
	end

	#
	# SQlite3 でシングルクオートはエスケープしないとダメらしい
	#

	def escape
		self.gsub(/'/, "''")
	end

end

class Fixnum
	def in_hash?(hash)
		hash.each do |item|
			return true if item == self
		end
		return false
	end
end
