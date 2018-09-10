# encoding: utf-8
require 'sinatra'
require 'sinatra/flash'
require 'sinatra/pundit'
require 'haml'
require 'resque'
require 'resque/server'
require 'logger'
require 'rack/protection'

require_relative 'models/master'
require_relative 'helpers/init'
require_relative 'routes/init'
require_relative 'jobs/init'

# Enable sessions
enable :sessions

use Rack::Protection::EscapedParams

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
before do
  unless %w[login register logout v1].include?(request.path_info.split('/')[1])
    @settings = Settings.first
    redirect '/login' unless validSession?
  end
end

# Catch pundit error and push 403 if not authorize
configure do
  error Pundit::NotAuthorizedError do
    status 403
    body 'Forbidden'
  end
end

# Add current_user in request env for Pundit
current_user do
  request.env['REMOTE_USER'] = current_user
end

# Set our key limit size
Rack::Utils.key_space_limit = 68719476736

# Quick check to see if there are any new wordlists
Resque.enqueue(WordlistImporter)
Resque.enqueue(WordlistChecksum)

# start our local agent
Resque.enqueue(LocalAgent)
