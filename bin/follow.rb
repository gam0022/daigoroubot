# -*- encoding: utf-8 -*-
require_relative '../lib/twitterbot'

# start message
logs "#start: follow.rb"
daigorou = TwitterBot.new(false, false, false)

cursor = "-1"
follower_ids = []
while cursor != 0 do
  followers = Twitter.follower_ids(nil, {cursor: cursor})
  cursor = followers.next_cursor
  follower_ids.concat(followers.ids)
end

cursor = "-1"
friend_ids = []
while cursor != 0 do
  friends = Twitter.friend_ids(nil, {cursor: cursor})
  cursor = friends.next_cursor
  friend_ids.concat(friends.ids)
end

new_follow = ( daigorou.config['Users']['follow'] | follower_ids ) - friend_ids - Twitter.friendships_outgoing.ids - daigorou.config['Users']['remove']

new_follow_count = 0

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
    new_follow_count += 1
    if new_follow_count == 10
      exit
    end
  end
end

new_unfollow = ( daigorou.config['Users']['remove'] & friend_ids ) | (friend_ids - follower_ids) - daigorou.config['Users']['follow']

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
