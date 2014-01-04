task :deploy do
  puts `rsync -avze 'ssh -p 3843' --delete --exclude-from './rsync-exclude' ./ root@gam0022.net:/root/daigoroubot`
end
