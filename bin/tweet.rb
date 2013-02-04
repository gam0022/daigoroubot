# -*- encoding: utf-8 -*-
require_relative '../lib/twitterbot'

# stat message
logs "#start: tweet.rb"

# 動作フラグ(ランダムなつぶやき、時間を付加、天気予報)
Flag = Struct.new(:regular, :time, :weather)
flag = Flag.new(false, false, false)

# キーワード(マルコフ連鎖の起点)
keyword = nil

str_update = nil
debug = false

#
# オプション解析
#
opt = OptionParser.new
opt.on('-r', '--regular') {|v| flag.regular = true}
opt.on('-t', '--time') {|v| flag.time = true}
opt.on('-w', '--weather') {|v| flag.weather = true}
opt.on('-d', '--debug') {|v| debug = true }
opt.on('-k VAL', '--keyword VAL') {|v| 
  keyword = v
  flag.regular = true
}
opt.parse!(ARGV)
str_update = ARGV[0]

logs "#Debug Mode" if debug
daigorou = TwitterBot.new(debug)

#
# 定期的なつぶやき
#
if flag.regular

  str_update = nil

  if !keyword
    keywords = daigorou.database.get_keywords
    stock = daigorou.database.get_stock

    if keywords.size != 0
      loop do
        faild = nil
        keyword = keywords.sample
        stock.each do |word|
          if keyword == word || keyword =~ /EOS$/ || keyword =~ /^\w+$/
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
    str_update = daigorou.talk(keyword)
    logs "keyword: [#{keyword}]"
    daigorou.database.add_stock(keyword)
  else
    logs "#error: faild to set keyword"
  end

  if !str_update
    str_update = daigorou.config['WordsOnFaildRegularTweet'].sample
  end

end

#
# 天気
#
str_update = daigorou.function.weather if flag.weather


#
# ツイート
#
if str_update
  daigorou.post(str_update, false, nil, flag.time, 1)
else
  logs "#error: faild to generate str_update"
end