# -*- coding: utf-8 -*-

class TwitterBot
  class Function

    # requirements
    include Math
    require 'unicode_math'

    def initialize(config)
      @sandbox = Sandbox.new
      @config = config
      @env = @config['env']

      eval @env

      # 計算機能のエイリアスの正規表現のパターンを生成
      unless @config['calculate']['alias_pattern']
        @config['calculate']['alias_pattern'] = @config['calculate']['alias'].keys.join('|')
      end
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
      jday = hash[day]

      text = ""

      begin
        uri = "http://weather.livedoor.com/forecast/webservice/json/v1?city=080020"
        open(uri) do |io|
          json = YAML.load(io)

          forecast = json['forecasts'].select{|e| e['dateLabel'] == jday}.first
          telop = forecast['telop']
          tmax = forecast['temperature']['max']['celsius'] rescue nil
          tmin = forecast['temperature']['min']['celsius'] rescue nil

          text = "#{jday}のつくばの天気は、#{telop}なのだ。"
          text += "最高気温#{tmax}℃" if tmax
          text += "、" if tmax && tmin
          text += "最低気温#{tmin}℃" if tmin
          text += "なのだ。" if tmax || tmin
          #text += "http://goo.gl/IPAuV"
          text += "http://goo.gl/9n3pD"
        end

      rescue
        return nil
      end

      return text
    end

  end
end
