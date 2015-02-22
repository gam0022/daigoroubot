# -*- coding: utf-8 -*-

#
# 所謂モンキーパッチ
#

#
# String
#
class String

  #
  # 英単語の場合、スペースをはさんで結合
  #
  def eappend(text)
    (text =~ /^\w+$/ && !self.empty?) ? "#{self} #{text}" : self+text
  end

  #
  # テキストから余分な文字を取り除く
  #
  def filter
    # エンコードをUTF-8 にして、改行とURLや#ハッシュダグや@メンションは消す
    self.gsub(/(\n|https?:\S+|from https?:\S+|#\w+|#|@\S+|^RT|なのだ|のだ|[؀-ۿ])/, "").gsub('&amp;', '&').gsub('&lt;', '<').gsub('&gt;', '>').strip
  end

  #
  # SQlite3 でシングルクオートはエスケープしないとダメらしい
  #
  def escape_for_sql
    self.gsub(/'/, "''")
  end

  #
  # 改行で区切れるように、指定した文字数の文字を得る。
  #
  def take_lines_at_length(n)
    tmp = ""
    pre = ""
    self.lines do |line|
      pre = tmp
      tmp += line
      if tmp.length > n
        return [pre, self[pre.length..1400]]
      end
    end
    return [self, ""]
  end

end

#
# Time
#
class Time
  def eql_day?(other)
    self.day == other.day && self.month == other.month && self.year == other.year 
  end
end
