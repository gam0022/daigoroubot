# -*- coding: utf-8 -*-

class TwitterBot
  class Users

    def initialize(filename)

      @filename = filename

      if File.exist?(@filename)
        open(@filename) do |io|
          @info = YAML.load(io)
        end
      else
        @info = {:status=>{}, :config=>{}}
      end
    end

    def save
      open(@filename, "w") do |io|
        io.write @info.to_yaml
      end
    end

    def status(id)
      if @info[:status][id]
        @info[:status][id]
      else
        @info[:status][id] = {:count => 0, :last => Time.now, :sum => 0}
      end
    end

    def config(id)
      if @info[:config][id]
        @info[:config][id]
      else
        @info[:config][id] = {:greeting => false}
      end
    end

  end
end
