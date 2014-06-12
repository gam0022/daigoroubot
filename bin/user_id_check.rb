# -*- encoding: utf-8 -*-
require_relative '../lib/twitterbot'

# start message
logs "#start: user_id_check.rb"
daigorou = TwitterBot.new(false, false, false)

daigorou.config['Users']['remove'].each do |id|
  puts id
  begin
    puts Twitter.user(id)
  rescue => e
    puts "error: id:#{id}"
  end
end

daigorou.config['Users']['follow'].each do |id|
  puts id
  begin
  rescue => e
    puts "error: id:#{id}"
  end
end

daigorou.config['Users']['ignore'].each do |id|
  puts id
  begin
  rescue => e
    puts "error: id:#{id}"
  end
end
