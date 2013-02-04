# -*- encoding: utf-8 -*-
require_relative '../lib/twitterbot'

# start message
logs "#start: response.rb"

#
#  オプション解析
#
debug = false
opt = OptionParser.new
opt.on('-d', '--debug') {|v| debug = true }
opt.parse!(ARGV)

logs "#Debug Mode" if debug

daigorou = TwitterBot.new(debug, true)

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
def generate_replay(status, daigorou, text, text_, screen_name, user_id, id, isRT, isMention, isMention_not_RT)

  # 自分に無関係なリプライを除くTL上の全ての発言に対して、単語に反応してリプライ
  if daigorou.users.config(user_id)[:greeting] && !isRT && ( status.user_mentions.empty? || isMention )
    str_update = search_table(daigorou.config['ReplayTable']['all'], text.delete("@#{daigorou.name} "))
    return str_update, isMention ? 3 : 1 if str_update
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
        daigorou.load_config(true)
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
daigorou.client.on_timeline_status do |status|

  text = status.text
  text_ = text.filter
  screen_name = status.user.screen_name
  user_id = status.user.id
  id = status.id

  isRT = status.retweeted_status
  isMention = status.user_mentions.any?{|user| user.screen_name==daigorou.name}
  isMention_not_RT = isMention && !isRT

  # textが無効だったら次へ
  next if !text || text == ''

  # タイムライン表示
  logs "[@#{screen_name}] #{text}"

  # ignoreリストに追加されたユーザか自分自身の発言なら無視する
  if daigorou.config['Users']['ignore'].include?(status.user.id) || screen_name == daigorou.name
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
    s = daigorou.users.status(user_id)
    if (s[:last] + interval < Time.now && s[:count] < count) || s[:last] + release < Time.now
      s[:count] = 0
    end

    s[:count] += 1
    s[:sum] += 1
    s[:last] = Time.now

    logs "count: #{s[:count]}"

    daigorou.users.save

    if s[:count] >= count
      logs "\t>>ignore(規制)"
      next
    end
  end

  # 返事を生成する
  str_update,try = 
    generate_replay(status, daigorou, text, text_, 
                    screen_name, user_id, id, isRT, isMention, isMention_not_RT)
  try = 3 unless try

  #
  # Reply
  #
  if str_update
    daigorou.post(str_update, screen_name, id, nil, try)
    # たまにふぁぼる
    daigorou.favorite(status) if rand(3) == 0
  end

  # Retweet
  daigorou.retweet(status) if text.index(Regexp.new(daigorou.config['RetweetKeyword']))

  #
  # Favorite
  #
  if text.index(/(ふぁぼ|足あと|踏めよ)/)
    if isMention_not_RT || text =~ /大五郎/
      # 「ふぁぼ」を含むリプライをふぁぼ爆撃する
      Twitter.user_timeline(screen_name, {:count => rand(40)}).each do |status| 
      daigorou.favorite(status)
      end
    else
      # 「ふぁぼ」を含むつぶやきをふぁぼる
      daigorou.favorite(status)
    end
  end

  # 学習させる
  daigorou.learn(text.filter) if !daigorou.debug && daigorou.users.config(user_id)[:learn]

  #
  # 寝る
  #
  if Time.now.hour >= 2 && Time.now.hour < 6 && !daigorou.debug
    str_update = "もう寝るのだ（Ｕ‐ω‐）...zzZZZ ~♪  #sleep"
    daigorou.post(str_update, nil, nil, true)
    exit
  end 

end

# Direct Message
daigorou.client.on_direct_message do |message|
  logs "#direct message:"

  text = message.text.filter
  sender_name = message.sender.screen_name
  sender_id = message.sender.id

  logs "[@#{sender_name}] #{message.text}"

  if sender_name == daigorou.name
    logs "\t>>ignore"
    next
  end

  reply_text = '日本語でおｋ（Ｕ＾ω＾）？'

  if text =~ /^(挨拶|あいさつ)(して.*|しろ.*|開始|許可)?$/
    daigorou.users.config(sender_id)[:greeting] = true
    reply_text = '設定完了。挨拶をするのだ（Ｕ＾ω＾）！'
  end

  if text =~ /(挨拶|あいさつ)(す[るん]な|しないで.*|停止|禁止)/
    daigorou.users.config(sender_id)[:greeting] = false
    reply_text = '設定完了。挨拶はしないのだ（Ｕ＾ω＾;）！'
  end

  if text =~ /^(学習|パクツイ)(して.*|しろ.*|開始|許可)?$/
    daigorou.users.config(sender_id)[:learn] = true
    reply_text = '設定完了。学習するのだ（Ｕ＾ω＾）！'
  end

  if text =~ /(パクツイ|学習)(す[るん]な|しないで.*|停止|禁止)/
    daigorou.users.config(sender_id)[:learn] = false
    reply_text = '設定完了。学習はしないのだ（Ｕ＾ω＾;）！'
  end

  # 連投防止のためのハッシュを付加
  reply_text = "#{reply_text} ##{Time.now.hash.to_s(36)}"

  logs "\tDM>>#{sender_name} #{reply_text}"
  Twitter.direct_message_create(sender_name, reply_text)

  daigorou.users.save

end

# Error Handling
daigorou.client.on_error do |message|
  time = logs("#error: #{message}")
  Twitter.direct_message_create(daigorou.config['author'], "#{time} #{$!}")
end

# Reconnect
daigorou.client.on_reconnect do |timeout, retries|
  logs "#reconnect: timeout:#{timeout}, retries:#{retries}"
end

daigorou.client.userstream
