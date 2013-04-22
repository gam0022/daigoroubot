#! /bin/bash
source /usr/local/rvm/environments/ruby-1.9.3-p0
cd $HOME/daigoroubot/bin
ruby tweet.rb -t "起きたのだ（Ｕ＾ω＾）わんわんお！ #okita"
ruby response.rb 1>> ../logs/response.log 2>> ../logs/response.log 
