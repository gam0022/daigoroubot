# -*- coding: utf-8 -*-

class TwitterBot
  class Function

    # requirements
    include Math
    require 'unicode_math'
    require 'time'

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

    #
    # 教室検索
    #
    def search_classroom(name)
      text = ""
      logs kamoku_db_filename  = BaseDir + "kamoku.db"
      kamoku_db_tablename = "kamoku"

      db = SQLite3::Database.new(kamoku_db_filename)
      db.busy_timeout(10000)
      db.results_as_hash = true

      term_now, mod_now = get_term_and_mod()

      begin
        name.gsub!("'", "''")
        sql = "select * from #{kamoku_db_tablename} where name like '#{name}%'"
        db.execute(sql) do |row|
          term = row["term"]
          if (term =~ /#{term_now}([ABC]+)/ && $1 != nil && $1.include?(mod_now)) || term.include?("集中") || term.include?("通年")
            text += "#{row["code"]} #{row["name"]} #{term} #{row["period"].gsub("\n", "/")} #{row["location"]}\n"
          end
        end

        db.close
      rescue => e
        logs e.backtrace.join("\n")
        db.close
      end

      return text.empty? ? nil : text
    end

    private

    TERM_BEGIN = {
      "春" => {
        "A" => "2015/04/07",
        "B" => "2015/05/23",
        "C" => "2015/07/04"
      },
      #"夏" => "2015/08/09",
      "秋" => {
        "A" => "2015/10/01",
        "B" => "2015/11/08",
        "C" => "2015/12/24"
      }
    }

    def get_term_and_mod

      term_now = "春"
      mod_now = "A"

      TERM_BEGIN.each do |term, mods|
        mods.each do |mod, date|
          if Time.now >= Time.parse(date)
            term_now = term
            mod_now = mod
          else
            return term_now, mod_now
          end
        end
      end
    end

  end
end
