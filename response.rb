# -*- encoding: utf-8 -*-
$:.unshift File.dirname(__FILE__)
require 'common.rb'

# start message
logs "#start: response.rb"
daigorou = TwitterBot.new

#
#  オプション解析
#

opt = OptionParser.new
opt.on('-d', '--debug') {|v| daigorou.debug = true }
opt.parse!(ARGV)

logs "#Debug Mode" if daigorou.debug

#
#	TLを取得
#

daigorou.connect do |status|				

	text = status['text']
	screen_name = status['user']['screen_name']
	id = status['id']

	# textが無効だったら次へ
	next if !text || text == ''

	str_update = nil

	# タイムライン表示
	logs "[@#{screen_name}] #{text}"

	# 自分に無関係なリプライを除くTL上の全ての発言に対して、単語に反応してリプライ
	if !(text =~ /@\S+/) || (text =~ /@#{daigorou.name}/)
		str_update = text.search_table(daigorou.config['ReplayTable']['all']) 
	end

	# メンションが来たら
	if text.index("@#{daigorou.name}") && !(text =~ /^RT/) && !str_update
		# adminからのコマンド受付
		if screen_name.in_hash?(daigorou.config['admin'])
			if text.index("kill")
				str_update = "はい。死にますのだ（ＵTωT) #daigoroubot_death"
				daigorou.post(str_update, screen_name, id, true)
				exit
			end
			if text.index("reload")
				str_update = "はい！設定再読み込みしますのだ！ #daigoroubot_reload_config"
				daigorou.post(str_update, screen_name, id, true)
				daigorou.load_config
				next
			end
		end

		# メンションに対して、単語に反応してリプライ
		str_update = text.search_table(daigorou.config['ReplayTable']['mention'])

		# 計算機能
		temp = text.gsub(/^@#{daigorou.name}/, "")
		if (temp =~ /^[\d*+-.\/() ]+$/)
			begin
				eval "str_update = (#{temp}).to_s"
			rescue SyntaxError
				# str_update = nil
			end
		end

		# マルコフ連鎖で返事を生成
		if !str_update
			temp = text
			mecab = MeCab::Tagger.new('-O wakati')
			# keyword: マルコフ連鎖の起点となる単語
			keyword = ["俺","僕", nil].sample
			# 75%の確率で、リプライに含まれる名詞or形容詞からキーワードを設定する。
			# 25%の確率で、上で生成した文章からさらに同様にしてキーワードを設定する。
			f = (rand(4) == 0) && !keyword ? 1 : 0
			(0 .. f).each do |i|
				node =  mecab.parseToNode(temp.filter)
				list = Array.new
				while node do
					# 含まれる名詞・形容詞を抜き出す
					if node.feature.to_s.toutf8 =~ /(名詞|形容詞)/ && !(node.surface.to_s.toutf8 =~ /(ー|EOS)/)
						list.push node.surface.toutf8
					end
					node = node.next
				end
				if list.size != 0
					keyword = list.sample
					logs "keyword(#{i}): [#{keyword}]"
					str_update = temp = daigorou.generate_phrase(keyword)
					logs "temp: #{temp}"
				else
					logs "#faild: faild to set keyword"
					break
				end
			end
		end

		if !str_update
			if keyword && !keyword.empty? && keyword != ' ' && f == 0
				str_update = [ "#{keyword}って、何なのだ？", "#{keyword}って何？ 美味しいの(U^ω^)？なのだ！？", "#{keyword}!?" ].sample
			elsif
				str_update = daigorou.config['WordsOnFaildReply'].sample
			end
		end

	end

	#
	#	リプライ
	#

	if str_update && screen_name != daigorou.name
		daigorou.post(str_update, screen_name, id)
	end

	# 学習させる
	daigorou.learn(text.filter) if screen_name != daigorou.name && !daigorou.debug

	#
	#	寝る
	#

	if Time.now.hour >= 2 && Time.now.hour < 6 && !daigorou.debug
		str_update = "もう寝るのだ（Ｕ‐ω‐）...zzZZZ ~♪  #sleep"
		daigorou.post(str_update, nil, nil, true)
		exit
	end	

end
