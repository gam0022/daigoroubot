# -*- encoding: utf-8 -*-
require_relative '../lib/twitterbot'

# start message
logs "#start: follow.rb"
daigorou = TwitterBot.new(false, false, false)

new_follow = ( daigorou.config['Users']['follow'] | daigorou.client_rest.follower_ids.ids ) - daigorou.client_rest.friend_ids.ids - daigorou.client_rest.friendships_outgoing.ids - daigorou.config['Users']['remove']

new_follow.each do |id|
  begin
    logs "[#{daigorou.client_rest.user(id).screen_name}]をフォローします。"
    daigorou.client_rest.follow(daigorou.client_rest.user(id).id)
  rescue
    logs "#error: #{$!}"
  else
    text = ["フォロー返したのだ！", "フォローありがとうなのだ！", "フォローしたのだ！"].sample
    daigorou.post("#{daigorou.client_rest.user(id).name}、#{text}", daigorou.client_rest.user(id).screen_name)
  end
end

new_unfollow = ( daigorou.config['Users']['remove'] & daigorou.client_rest.friend_ids.ids ) | (daigorou.client_rest.friend_ids.ids - daigorou.client_rest.follower_ids.ids ) - daigorou.config['Users']['follow']

new_unfollow.each do |id|
  begin
    logs "[#{daigorou.client_rest.user(id).screen_name}]をリムーブします。"
    daigorou.client_rest.unfollow(daigorou.client_rest.user(id).id)
  rescue
    logs "#error: #{$!}"
  end
end
