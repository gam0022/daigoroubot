# -*- coding: utf-8 -*-

#
# 所謂モンキーパッチ
#

#
# String拡張
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
    self.gsub(/(\n|https?:\S+|from https?:\S+|#\w+|#|@\S+|^RT|なのだ|のだ)/, "").gsub('&amp;', '&').gsub('&lt;', '<').gsub('&gt;', '>').strip
  end

  #
  # SQlite3 でシングルクオートはエスケープしないとダメらしい
  #
  def escape_for_sql
    self.gsub(/'/, "''")
  end

end
