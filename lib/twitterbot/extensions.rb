# -*- coding: utf-8 -*-

#
# 所謂モンキーパッチ
#

module StringFixnum

  #
  # テキストが指定した配列の要素のどれかと一致するならtrueを返す
  #

  def in_hash?(hash)
    hash.each do |item|
      return true if item == self
    end
    return false
  end
end

#
# String拡張
#

class String

  include StringFixnum

  #
  # 英単語の場合、スペースをはさんで結合
  #

  def eappend(text)
    (text =~ /^\w+$/ && !self.empty?) ? "#{self} #{text}" : "#{self}#{text}"
  end

  #
  # テキストから余分な文字を取り除く
  #

  def filter
    # エンコードをUTF-8 にして、改行とURLや#ハッシュダグや@メンションは消す
    self.gsub(/(\n|https?:\S+|from https?:\S+|#\w+|#|@\S+|^RT|なのだ|のだ)/, "").gsub('&amp;', '&').gsub('&lt;', '<').gsub('&gt;', '>')
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
  # テキストにテーブル()の要素が含まれていたなら、
  # そのテーブルのペアの要素をランダムに返す
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

  def escape_for_db
    self.gsub(/'/, "''")
  end

end

class Fixnum
  include StringFixnum
end
