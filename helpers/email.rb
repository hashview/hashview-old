require 'rubygems'
require 'sinatra'
require './model/master'
require 'pony'

def sendEmail(jobid)
  job = Jobs.first(id: jobid)
  smtp_settings = Settings.first
  recipient = Users.first(name: job.last_updated_by)
  smtp_server, smtp_port = smtp_settings.smtp_server.split(':')
#  smtp_port = smtp_settings.smtp_server.split(:)[1]

  Pony.options = {
    :via => :smtp,
    :via_options => {
      :address              => smtp_server,
      :port                 => smtp_port,
      :enable_starttls_auto => false, # true, false
      :user_name            => smtp_settings.smtp_user,
      :password             => smtp_settings.smtp_pass,
#      :authentication       => :plain, # :plain, :login, :cram_md5, no auth by default
#      :domain               => "localhost.localdomain"
    }
  }

  Pony.mail :to => recipient.email,
            :from => smtp_settings.smtp_username,
            :subject => "Your Job: #{job.name} has completed"
end
