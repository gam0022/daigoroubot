# -*- encoding: utf-8 -*-
require_relative '../lib/twitterbot'

# start message
logs "#start: follow.rb"
daigorou = TwitterBot.new(false, false, false)

new_follow = ( daigorou.config['Users']['follow'] | Twitter.follower_ids.ids ) - Twitter.friend_ids.ids - Twitter.friendships_outgoing.ids - daigorou.config['Users']['remove']

new_follow.each do |id|
  begin
    logs "[#{Twitter.user(id).screen_name}]をフォローします。"
    Twitter.follow(Twitter.user(id).id)
  rescue => e
    logs "#error in follow: #{$!}"
    logs "id: #{id}"
    logs "#{e.class}"
    logs "#{e.backtrace.join("\n")}"
  else
    text = ["フォロー返したのだ！", "フォローありがとうなのだ！", "フォローしたのだ！"].sample
    daigorou.post("#{Twitter.user(id).name}、#{text}", Twitter.user(id).screen_name)
  end
end

new_unfollow = ( daigorou.config['Users']['remove'] & Twitter.friend_ids.ids ) | (Twitter.friend_ids.ids - Twitter.follower_ids.ids ) - daigorou.config['Users']['follow']

new_unfollow.each do |id|
  begin
    logs "[#{Twitter.user(id).screen_name}]をリムーブします。"
    Twitter.unfollow(Twitter.user(id).id)
  rescue => e
    logs "#error in remove: #{$!}"
    logs "id: #{id}"
    logs "#{e.class}"
    logs "#{e.backtrace.join("\n")}"
  end
end
