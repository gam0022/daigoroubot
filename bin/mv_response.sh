#! /bin/bash
source /usr/local/rvm/environments/ruby-1.9.3-p0
cd $HOME/daigoroubot/bin
ruby mv_response.rb 1>> ../logs/tmp.log 2>>../logs/tmp.log
