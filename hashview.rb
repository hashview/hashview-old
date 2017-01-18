# encoding: utf-8
#require 'sinatra/base'
require 'sinatra'
require 'sinatra/flash'
require 'haml'
#require_relative 'routes/init'
#require_relative 'helpers/init'

#class HashView < Sinatra::Application
#class HashView < Sinatra::Base
#  enable :sessions

#  configure :production do
#    set :haml, { :ugly=>true }
#    set :clean_trace, true
#  end

#  configure :development do
#    # ...
#  end

#  helpers do
#    include Rack::Utils
#    alias_method :h, :escape_html
#  end
#end

require_relative 'models/master'
require_relative 'helpers/init'
require_relative 'routes/init'
#require_relative 'helpers/sinatra_ssl'
