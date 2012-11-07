# -*- encoding: utf-8 -*-
$:.unshift File.dirname(__FILE__)
require 'twitterbot.rb'

# start message
logs "#start: response.rb"
daigorou = TwitterBot.new
sandbox = Sandbox.new

#
#  オプション解析
#

opt = OptionParser.new
opt.on('-d', '--debug') {|v| daigorou.debug = true }
opt.parse!(ARGV)

logs "#Debug Mode" if daigorou.debug

#
# 返事を生成
#

def generate_replay(status, daigorou, sandbox)

  text = status['text']
  text_ = text.filter
  screen_name = status['user']['screen_name']
  id = status['id']

  # 自分に無関係なリプライを除くTL上の全ての発言に対して、単語に反応してリプライ
  if !(text =~ /^RT/) && ( !(text =~ /@\S+/) || (text =~ /@#{daigorou.name}/) )
    str_update = text.gsub(/@daigoroubot/, '').search_table(daigorou.config['ReplayTable']['all']) 
    return str_update, 1 if str_update
  end

  # 複雑な機能
  str_update = daigorou.do_complex(text_, 'all')
  return str_update if str_update

  # メンションが来たら
  if text.index("@#{daigorou.name}") && !(text =~ /^RT/)
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
        #next
        return nil
      end
    end

    # メンションに対して、単語に反応してリプライ
    str_update = text.search_table(daigorou.config['ReplayTable']['mention'])
    return str_update if str_update

    # 電卓機能
    str_update = sandbox.calculate(text_.convert_operator(daigorou.config), daigorou.config['Calculate']['env'])
    return str_update if str_update

    # 天気予報
    if text =~ /(天気|てんき|weather)/
      day =
        text =~ /(今日|本日|きょう|ほんじつ|today)/ ? "today" : 
        text =~ /(明日|(1|１|一|壱)日後|あした|あす|tomorrow)/ ? "tomorrow" : 
        text =~ /(明後日|(2|２|二|弐)日後|あさって|day after tomorrow|dayaftertomorrow)/ ? "dayaftertomorrow" : nil

      str_update = 
        day || (text =~ /(筑波|つくば)/) || !(text =~ /の/) ? 
        weather(day) : 
        "ごめんなのだ（Ｕ´・ω・`)…　(今日|明日|明後日)のつくばの天気にしか対応してないのだ…"
      return str_update if str_update
    end

    # 複雑な機能
    str_update = daigorou.do_complex(text_)
    return str_update if str_update

    # マルコフ連鎖で返事を生成
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
      if list.size != 0 || keyword
        keyword = list.sample if list.size != 0
        logs "keyword(#{i}): [#{keyword}]"
        str_update = temp = daigorou.generate_phrase(keyword)
        logs "temp: #{temp}"
        break unless temp
      else
        logs "#faild: faild to set keyword"
        break
      end
    end
    return str_update if str_update

    if keyword && !keyword.empty? && keyword != ' ' && f == 0
      return [ "#{keyword}って、何なのだ？", "#{keyword}って何？ 美味しいの(U^ω^)？なのだ！？", "#{keyword}!?" ].sample
    else
      return daigorou.config['WordsOnFaildReply'].sample
    end

    return nil

  end
end

#
# TLを取得
#

daigorou.connect do |status|        

  text = status['text']
  screen_name = status['user']['screen_name']
  id = status['id']

  # textが無効だったら次へ
  next if !text || text == ''

  # タイムライン表示
  logs "[@#{screen_name}] #{text}"

  # ignoreリストに追加されたユーザか自分自身の発言なら無視する
  if status['user']['id'].in_hash?(daigorou.users("ignore")) || screen_name == daigorou.name
    logs "  >>ignore"
    next
  end

  # 返事を生成する
  str_update,try = generate_replay(status, daigorou, sandbox)
  try = 5 unless try

  #
  # リプライ
  #

  if str_update
    daigorou.post(str_update, screen_name, id, nil, try)
  end

  #
  # RT
  #

  Twitter.retweet(id) if text.index("#daigoroubot") && !daigorou.debug

  # 学習させる
  daigorou.learn(text.filter) if !daigorou.debug

  #
  # 寝る
  #

  if Time.now.hour >= 2 && Time.now.hour < 6 && !daigorou.debug
    str_update = "もう寝るのだ（Ｕ‐ω‐）...zzZZZ ~♪  #sleep"
    daigorou.post(str_update, nil, nil, true)
    exit
  end 

end
