require 'pony'

def sendEmail(recipient, sub, msg)
  smtp_settings = Settings.first
  smtp_server, smtp_port = smtp_settings.smtp_server.split(':')
  use_tls = true if smtp_settings.smtp_use_tls == '1'
  use_tls = false if smtp_settings.smtp_use_tls == '0'
  p "SMTP_SERVER: " + smtp_server
  p "SMTP_PORT: " + smtp_port
  p "USE_TLS: " + use_tls.to_s
  p "TO: " + recipient
  p "FROM: " + smtp_settings.smtp_user
  p "SUB: " + sub
  p "msg: " + msg


  if ! smtp_settings.smtp_user.nil? && ! smtp_settings.smtp_pass.nil?
    Pony.options = {
      :via => :smtp,
      :via_options => {
        :address              => "#{smtp_server}",
        :port                 => "#{smtp_port}",
        :enable_starttls_auto => use_tls.to_s,
        :user_name            => "#{smtp_settings.smtp_user}",
        :password             => "#{smtp_settings.smtp_pass}",
        :authentication       => "#{smtp_settings.smtp_auth_type}", 
        :domain               => "localhost.localdomain"
      }
    }
  else
    Pony.options = {
      :via => :smtp,
      :via_options => {
        :address              => "#{smtp_server}",
        :port                 => "#{smtp_port}",
        :enable_starttls_auto => false # true, false
      }
    }
  end

  Pony.mail :to => recipient,
            :from => smtp_settings.smtp_user,
            :subject => sub,
            :body => msg
end
        
recipient = 'hans.lakhan.synercomm.@gmail.com'
sub = 'You job has completed'
msg = '45 out of 90 hashes cracked'                                                                                         
sendEmail(recipient, sub, msg)  
