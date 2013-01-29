# -*- coding: utf-8 -*-
require 'sqlite3'

class TwitterBot
  class DataBase

    # フィールド
    @filename = "";

    # 初期化
    def initialize(filename)

      @filename = filename;

      db = SQLite3::Database.new(@filename)
      db.busy_timeout(100000)

      # テーブルの有無を確認
      begin
        db.execute("create table markov (id integer primary key, head text, body text, tail text)")
        db.execute("create table stock (id integer primary key, head text)")
        db.execute("create index head on markov(head)")
        db.execute("create index head_and_body on markov(head,body)")
        db.execute("create index stock_head on stock(head)")
      rescue SQLite3::SQLException
        logs "既にテーブルがあるようです"
      else
        logs "テーブルを新規作成しました。"
      end

      # テーブルの行数を確認
      begin
        limit_rows(db, "markov", 1000000)
        limit_rows(db, "stock", 30)
      rescue SQLite3::BusyException
        logs "SQLite3::BusyException"
      end

      db.close

    end

    # テーブルの行数を制限する
    def limit_rows(db, table, max = 100000)
      db.execute("select count(*) from #{table}") do |row|
        if row[0] > max
          db.execute("select min(id) from #{table}") do |min|
            db.execute("delete from #{table} where id < #{row[0]-max+min[0]}")
          end
        end
      end
    end

    # データベースにアクセスする
    def open
      db = SQLite3::Database.new(@filename)
      db.busy_timeout(100000)
      yield db
      db.close
    end

    #
    # keywords と stock を取得/追加
    #

    def get_keywords
      list = Array.new
      open do |db|
        db.execute("select body from markov where head = '' order by id desc limit 100") do |body|
          list.push body[0]
        end
      end
      return list
    end

    def get_stock
      list = Array.new
      open do |db|
        db.execute("select head from stock") do |hash|
          list.push hash[0]
        end
      end
      return list
    end

    def add_stock(keyword)
      open do |db|
        hash = {:head => keyword}
        sql = "insert into stock values (:id, :head)"
        db.execute(sql, hash)
      end
    end

  end
end
