# encoding: utf-8
require 'sinatra'
require 'sinatra/flash'
require 'haml'
require_relative 'models/master'
require_relative 'helpers/init'
require_relative 'routes/init'

enable :sessions

before /^(?!\/(login|register|logout))/ do
  if !validSession?
    redirect to('/login')
  else
    settings = Settings.first
    if (settings && settings.hcbinpath.nil?) || settings.nil?
      flash[:warning] = "Annoying alert! You need to define hashcat\'s binary path in settings first. Do so <a href=/settings>HERE</a>"
    end
  end
end

