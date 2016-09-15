#require 'rubygems'
#require 'sinatra'
#require './model/master.rb'
require 'pony'

def sendEmail(recipient, sub, msg)
  smtp_settings = Settings.first
  smtp_server, smtp_port = smtp_settings.smtp_server.split(':')
  p "RECIPIENT: " + recipient
  p "SUB: " + sub
  p "msg: " + msg


  Pony.options = {
    :via => :smtp,
    :via_options => {
      :address              => "#{smtp_server}",
      :port                 => "#{smtp_port}",
      :enable_starttls_auto => false # true, false
      #:user_name            => smtp_settings.smtp_user,
      #:password             => smtp_settings.smtp_pass,
#      :authentication       => :plain, # :plain, :login, :cram_md5, no auth by default
#      :domain               => "localhost.localdomain"
    }
  }

  Pony.mail :to => recipient,
            :from => smtp_settings.smtp_user,
            :subject => sub,
            :body => msg
end
