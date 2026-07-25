#!/usr/bin/env ruby
InstallationConfig.all.each { |c| puts "#{c.name} => #{c.value.class}: #{c.value.inspect[0..80]}" }
