# -*- encoding: utf-8 -*-
require_relative '../lib/twitterbot'

# start message
logs "#start: response.rb"
daigorou = TwitterBot.new
users = {}

#
#  オプション解析
#

opt = OptionParser.new
opt.on('-d', '--debug') {|v| daigorou.debug = true }
opt.parse!(ARGV)

logs "#Debug Mode" if daigorou.debug

#
# ここで言うテーブルは次のようなデータ構造となっている
#
# - 
#   - [キーワドA, キーワドA...]
#   - [返り値A, 返り値A...]
# - 
#   - [キーワドB, キーワドB...]
#   - [返り値B, 返り値B...]
# -
#   - ...
#   - ...
# ...
#
def search_table(table, text)
  table.each do |row|
    if row[0].any? {|val| text.index(val)}
      return row[1].sample
    end
  end
  return nil
end

#
# 文章を元にキーワードを設定する
#
def get_keyword(daigorou, text, rec, stack)
  return stack.pop unless text
  mecab = MeCab::Tagger.new('-O wakati')
  node =  mecab.parseToNode(text.filter)
  list = []
  while node do
    # 含まれる名詞・形容詞を抜き出す
    if node.feature.to_s.toutf8 =~ /(名詞|形容詞)/ && !(node.surface.to_s.toutf8 =~ /(ー|EOS)/)
      list << node.surface.toutf8
    end
    node = node.next
  end

  if list.size > 0
    # キーワードを1つ以上あった
    keyword = list.sample
    stack << keyword
    if rec == 0
      return keyword
    else
      return get_keyword(daigorou, daigorou.talk(keyword), rec-1, stack)
    end
  else
    # キーワードがなければ前のキーワードを返す
    return stack.pop
  end
end

#
# 返事を生成
#
def generate_replay(status, daigorou)

  text = status['text']
  text_ = text.filter
  screen_name = status['user']['screen_name']
  id = status['id']

  isRT = status['retweeted_status']
  isMention = status['entities']['user_mentions'].any?{|user| user['screen_name']==daigorou.name}
  #isMention = text.index("@#{daigorou.name} ")
  isMention_not_RT = isMention && !isRT

  # 自分に無関係なリプライを除くTL上の全ての発言に対して、単語に反応してリプライ
  if !isRT && ( status['entities']['user_mentions'].empty? || isMention )
    str_update = search_table(daigorou.config['ReplayTable']['all'], text.delete("@#{daigorou.name} "))
    return str_update, 1 if str_update
  end

  # 複雑な機能
  str_update = daigorou.function.command(text_, 'all')
  return str_update if str_update

  #
  # メンションが来たら
  #
  if isMention_not_RT 
    # adminからのコマンド受付
    if daigorou.config['admin'].include?(screen_name)
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
    str_update = search_table(daigorou.config['ReplayTable']['mention'], text)
    return str_update if str_update

    # 電卓機能
    str_update = daigorou.function.calculate(text_)
    return str_update if str_update

    # 天気予報
    if text =~ /(天気|てんき|weather)/
      day =
      text =~ /(今日|本日|きょう|ほんじつ|today)/ ? "today" : 
      text =~ /(明後日|(2|２|二|弐)日後|あさって|day after tomorrow|dayaftertomorrow)/ ? "dayaftertomorrow" : 
      text =~ /(明日|(1|１|一|壱)日後|あした|あす|tomorrow)/ ? "tomorrow" : nil

      str_update = 
        day || (text =~ /(筑波|つくば)/) || !(text =~ /の/) ? 
        daigorou.function.weather(day) : 
        "ごめんなのだ（Ｕ´・ω・`)…　(今日|明日|明後日)のつくばの天気にしか対応してないのだ…"
      return str_update if str_update
    end

    # 複雑な機能
    str_update = daigorou.function.command(text_, 'mention')
    return str_update if str_update

    # マルコフ連鎖で返事を生成
    rec = (3*0.5**rand(5)).to_i
    logs "keyword設定の再帰回数: #{rec}"
    keyword = get_keyword(daigorou, text, rec, [["俺","僕", nil].sample])
    if keyword
      logs "keyword:[#{keyword}]"
      str_update = daigorou.talk(keyword)
    else
      logs "#faild: faild to set keyword"
    end
    return str_update if str_update

    if keyword && !keyword.empty? && keyword != ' '
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
  text_ = text.filter
  screen_name = status['user']['screen_name']
  id = status['id']

  isRT = status['retweeted_status']
  isMention = status['entities']['user_mentions'].any?{|user| user['screen_name']==daigorou.name}
  isMention_not_RT = isMention && !isRT

  # textが無効だったら次へ
  next if !text || text == ''

  # タイムライン表示
  logs "[@#{screen_name}] #{text}"

  # ignoreリストに追加されたユーザか自分自身の発言なら無視する
  if daigorou.users("ignore").include?(status['user']['id']) || screen_name == daigorou.name
    logs "\t>>ignore"
    next
  end

  #
  # リプ爆撃対策
  #
  if isMention_not_RT
    interval= daigorou.config['MentionLimit']['interval']
    count   = daigorou.config['MentionLimit']['count']
    release = daigorou.config['MentionLimit']['release']

    # interval秒間隔でcount回数リプライがある場合、release秒間返信しない
    if !users[screen_name] || 
      (users[screen_name]['mentioned']['last'] + interval < Time.now && users[screen_name]['mentioned']['count'] < count) ||
      users[screen_name]['mentioned']['last'] + release < Time.now 

      users[screen_name] = {} unless users[screen_name]
      users[screen_name]['mentioned'] = {'count' => 0}
    end

    users[screen_name]['mentioned']['count'] += 1
    users[screen_name]['mentioned']['last'] = Time.now
    logs "count:#{users[screen_name]['mentioned']['count']}"
    if users[screen_name]['mentioned']['count'] >= count
      logs "\t>>ignore(規制)"
      next
    end
  end

  # 返事を生成する
  str_update,try = generate_replay(status, daigorou)
  try = 5 unless try

  #
  # リプライ
  #
  if str_update
    daigorou.post(str_update, screen_name, id, nil, try)
    # たまにふぁぼる
    daigorou.favorite(status) if rand(3) == 0
  end

  # RT
  daigorou.retweet(status) if text.index(Regexp.new(daigorou.config['RetweetKeyword']))

  #
  # FAV
  #
  if text.index(/(ふぁぼ|足あと|踏めよ)/)
    if text =~ /(@#{daigorou.name}|大五郎)/
      # 「ふぁぼ」を含むリプライをふぁぼ爆撃する
      # 一時凍結。対策を考える。
      #Twitter.user_timeline(screen_name, {:count => rand(40)}).each do |status| 
      #daigorou.favorite(status)
      #end
    else
      # 「ふぁぼ」を含むつぶやきをふぁぼる
      daigorou.favorite(status)
    end
  end

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
