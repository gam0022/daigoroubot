#! /bin/bash
source /usr/local/rvm/environments/ruby-1.9.3-p0
cd $HOME/daigoroubot/bin
ruby follow.rb $* 1>> ../logs/follow.log 2>> ../logs/follow.log
