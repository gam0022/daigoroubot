# -*- encoding: utf-8 -*-
$:.unshift File.dirname(__FILE__)
require 'common.rb'

# stat message
logs "#start: tweet.rb"
daigorou = TwitterBot.new

regular = nil	#ランダムなつぶやき
time = nil		#時間を付加
#daigorou.debug = nil	#デバッグモード


#
#	オプション解析
#

str_update = nil

ARGV.each do |arg|
	if arg =~ /(^-)(\w*)/
		case $2
		when 'r', 'regular'
			regular = true
		when 't', 'time'
			time = true
		when 'd', 'debug'
			daigorou.debug = true
		end
	else
		str_update = arg.toutf8
	end
end

#
#	定期的なつぶやき
#

if regular

	keyword = nil
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

	if keyword
		str_update = daigorou.generate_phrase(keyword)
		logs "keyword: [#{keyword}]"
		daigorou.add_stock(keyword)
	else
		logs "#error: faild to set keyword"
	end

	if str_update == nil
		str_update = daigorou.config['WordsOnFaildRegularTweet'].sample
	end

end

#
#	ツイート
#

if str_update
	daigorou.post(str_update, nil, nil, time)
else
	logs "#error: faild to generate str_update"
end
