#! /bin/bash
source /usr/local/rvm/environments/ruby-1.9.3-p0
cd $HOME/daigoroubot/bin
ruby tweet.rb $* 1>> ../logs/tweet.log 2>> ../logs/tweet.log
