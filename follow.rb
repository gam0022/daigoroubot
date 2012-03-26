# -*- encoding: utf-8 -*-
$:.unshift File.dirname(__FILE__)
require 'common.rb'
require 'twitter'

daigorou = TwitterBot.new

Twitter.configure do |configer|
  configer.consumer_key				= daigorou.CONSUMER_KEY			 
  configer.consumer_secret		= daigorou.CONSUMER_SECRET	 
  configer.oauth_token				= daigorou.OAUTH_TOEKN			 
  configer.oauth_token_secret	= daigorou.OAUTH_TOEKN_SECRET
end

new_follow = Twitter.follower_ids.ids - Twitter.friend_ids.ids - Twitter.friendships_outgoing.ids

new_follow.each do |id|
	begin
		logs "[#{Twitter.user(id).screen_name}]をフォローします。"
		Twitter.follow(Twitter.user(id).id)
	rescue
		logs "#error: #{$!}"
	else
		text = ["フォロー返したのだ！", "フォローありがとうなのだ！", "フォローしたのだ！"].sample
		daigorou.post("#{Twitter.user(id).name}、#{text}", Twitter.user(id).screen_name)
	end
end

new_unfollow = Twitter.friend_ids.ids - Twitter.follower_ids.ids - daigorou.config['kataomoi_ids']

new_unfollow.each do |id|
	begin
		logs "[#{Twitter.user(id).screen_name}]をリムーブします。"
		Twitter.unfollow(Twitter.user(id).id)
	rescue
		logs "#error: #{$!}"
	end
end
