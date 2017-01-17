# encoding: utf-8
require_relative 'email'
HashView.helpers SendEmail

require_relative 'hashimporter'
HashView.helpers HashImorter

require_relative 'hc_stdout_parser'
HashView.helpers HcStdoutParser

require_relative 'sinatra_ssl'
HashView.helpers Sinatra
