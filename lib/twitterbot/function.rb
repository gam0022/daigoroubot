# -*- coding: utf-8 -*-

class TwitterBot

  class Function

    # requirements
    include Math
    require 'unicode_math'
    require "rexml/document"
    include REXML

    def initialize(config)
      @sandbox = Sandbox.new
      @config = config
      @env = @config['calculate']['env']

      eval @env
    end

    #
    # 計算機能
    #

    def convert_operator(text, config)
      result = text.
        gsub(/[\n\r]+/, "").delete("　").
        gsub(/[=は?？]+$/, "").
        tr("０-９", "0-9").tr("（）", "()").
        gsub(/(#{config['calculate']['alias_pattern']})/, config['calculate']['alias'])
      config['calculate']['alias_regexp'].each do |key, val|
        result.gsub!(Regexp.new(key)) {|m| eval(val)}
      end
      result
    end

    def calculate(formula)
      logs "formula:" + formula = convert_operator(formula, @config)
      return nil if formula =~ /sleep/

        begin
          return @sandbox.safe(@config['Sandbox']['level'], @config['Sandbox']['timeout']) {
            eval "(#{formula}).to_s"
          }
        rescue ZeroDivisionError
          "ゼロ除算やめて!!なのだっ！（Ｕ>ω<;）"
        rescue SecurityError
          "その操作は禁止されているのだ(U´・ω・`)"
        rescue NoMemoryError
          return "ちょwなのだ（Ｕ>ω<;）"
        rescue SyntaxError, StandardError
          nil
        end
    end

    #
    # 複雑な動作を実行
    #

    def command(text, type='mention')
      return nil unless @config['command'][type]

      @config['command'][type].each do |cmd|
        if Regexp.new(cmd[0]) =~ text
          level   = @config['Sandbox']['level']
          timeout = @config['Sandbox']['timeout']
          begin
            return @sandbox.safe(level, timeout) {
              eval cmd[1]
            }
          rescue ZeroDivisionError
            return "ゼロ除算やめて!!なのだっ！（Ｕ>ω<;）"
          rescue SecurityError
            return "その操作は禁止されているのだ(U´・ω・`)"
          rescue NoMemoryError
            return "ちょwなのだ（Ｕ>ω<;）"
          rescue SyntaxError, StandardError
            nil
          end
        end
      end
      return nil
    end

    #
    # 天気予報機能
    #

    def weather(day=nil)
      # dayが指定されていなければ設定する
      day = Time.now.hour <= 15 ? "today" : "tomorrow" unless day

      # 英語=>日本語の変換
      hash = {"today" => "今日", "tomorrow" => "明日", "dayaftertomorrow" => "明後日"}

      begin
        f = open("http://weather.livedoor.com/forecast/webservice/rest/v1?city=55&day=#{day}")
        doc = Document.new(f.read)
        f.close

        return nil unless (telop = doc.elements['/lwws/telop'].get_text)
        tmax = doc.elements['/lwws/temperature/max/celsius'].get_text
        tmin = doc.elements['/lwws/temperature/min/celsius'].get_text

        text = "#{hash[day]}のつくばの天気は、#{telop}なのだ。"
        text += "最高気温#{tmax}℃" if tmax
        text += "、" if tmax && tmin
        text += "最低気温#{tmin}℃" if tmin
        text += "なのだ。" if tmax || tmin
        text += "http://goo.gl/IPAuV"
      rescue
        return nil
      end
      return text
    end
  end
end
