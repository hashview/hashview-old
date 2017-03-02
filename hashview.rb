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


