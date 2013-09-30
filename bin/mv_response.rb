require 'date'

puts original_filename = "../logs/response.log"
puts copyto_filename = "../logs/response-#{Date.today - 1}.log"

puts `/bin/mv #{original_filename} #{copyto_filename}`
