# -*- encoding: utf-8 -*-
$:.unshift File.dirname(__FILE__)
require 'common.rb'

# stat message
logs "#start: tweet.rb"
daigorou = TwitterBot.new

regular = false	#ランダムなつぶやき
time = false		#時間を付加
#daigorou.debug = nil	#デバッグモード
keyword = nil


#
#	オプション解析
#

str_update = nil

opt = OptionParser.new
opt.on('-r', '--regular') {|v| regular = true}
opt.on('-t', '--time') {|v| time = true}
opt.on('-d', '--debug') {|v| daigorou.debug = true }
opt.on('-k VAL', '--keyword VAL') {|v| 
	keyword = v
	regular = true
}
opt.parse!(ARGV)
str_update = ARGV[0]

logs "#Debug Mode" if daigorou.debug

#
#	定期的なつぶやき
#

if regular

	str_update = nil

	if !keyword
		keywords = daigorou.get_keywords
		stock = daigorou.get_stock

		if keywords.size != 0
			loop do
				faild = nil
				keyword = keywords.sample
				stock.each do |word|
					if keyword == word || keyword =~ /EOS$/
						faild = true
						logs "#faild: set to keyword [#{word}]"
						break
					end
				end
				break unless faild
			end
		end
	end

	if keyword
		str_update = daigorou.generate_phrase(keyword)
		logs "keyword: [#{keyword}]"
		daigorou.add_stock(keyword)
	else
		logs "#error: faild to set keyword"
	end

	if !str_update
		str_update = daigorou.config['WordsOnFaildRegularTweet'].sample
	end

end

#
#	ツイート
#

if str_update
	daigorou.post(str_update, false, nil, time)
else
	logs "#error: faild to generate str_update"
end
