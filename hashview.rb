# encoding: utf-8
require 'sinatra'
require 'sinatra/flash'
require 'haml'
require 'resque'
require 'resque/server'
require 'logger'

require_relative 'models/master'
require_relative 'helpers/init'
require_relative 'routes/init'
require_relative 'jobs/init'

# Enable sessions
enable :sessions

# Presume production if not told otherwise
if ENV['RACK_ENV'].nil?
  set :environment, :production
  ENV['RACK_ENV'] = 'production'
end

if isOldVersion?
  # puts 'You need to perform some upgrade steps. Check instructions <a href=\"https://github.com/hashview/hashview/wiki/Upgrading-Hashview\">here</a>"
  puts "\n\nYour installation is out of date, please run the following upgrade task.\n"
  puts "RACK_ENV=#{ENV['RACK_ENV']} rake db:upgrade\n\n\n"
  exit
end

# make sure the binary path is set in the configuration file
options = JSON.parse(File.read('config/agent_config.json'))
if options['hc_binary_path'].empty? || options['hc_binary_path'].nil?
  puts '!!!!!!!!!! ERROR !!!!!!!!!!!!!!'
  puts '[!] You must defined the full path to your hashcat binary. Do this in your config/agent_config.json file'
  puts '!!!!!!!!!! ERROR !!!!!!!!!!!!!!'
  exit 0
end

# Check for valid session before proccessing
before /^(?!\/(login|register|logout|v1\/))/ do
  @settings = Settings.first
  if !validSession?
    redirect to('/login')
  end
end

# Set our key limit size
Rack::Utils.key_space_limit = 68719476736

# start our local agent
Resque.enqueue(LocalAgent)