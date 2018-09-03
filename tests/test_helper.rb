# test_helper.rb
ENV['RACK_ENV'] = 'test'
require 'minitest/autorun'
require 'rack/test'
require 'factory_bot'

require File.expand_path('../hashview.rb', __dir__)
