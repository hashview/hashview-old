# encoding: utf-8
require 'sinatra'
require 'sinatra/flash'
require 'haml'
require 'resque'
require 'resque/server'

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

# Verify upgrade steps have been performed to support distributed cracking
unless File.exist?('config/agent_config.json')
  puts "You need to upgrade your installation to support distributed cracking. Run the following:\n"
  puts "RACK_ENV=#{ENV['RACK_ENV']} rake db:provision_agent"
  exit
end

# Check for valid session before proccessing
before /^(?!\/(login|register|logout|v1))/ do
  @settings = Settings.first
  if !validSession?
    redirect to('/login')
  else
    hc_settings = HcSettings.first
    if (hc_settings && hc_settings.hc_binpath.nil?) || hc_settings.nil?
      flash[:warning] = 'Annoying alert! You need to define hashcat\'s binary path in settings first. Do so <a href=/settings>HERE</a>'
    end
  end
end

# start our local agent
Resque.enqueue(LocalAgent)