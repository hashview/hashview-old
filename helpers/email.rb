require 'pony'

def sendEmail(recipient, sub, msg)
  smtp_settings = Settings.first
  smtp_server, smtp_port = smtp_settings.smtp_server.split(':')
  use_tls = true if smtp_settings.smtp_use_tls == '1'
  use_tls = false if smtp_settings.smtp_use_tls == '0'

  if smtp_settings.smtp_auth_type != 'None'
    p "HERE I AM"
    Pony.options = {
      :via => :smtp,
      :via_options => {
        :address              => "#{smtp_server}",
        :port                 => "#{smtp_port}",
        :enable_starttls_auto => use_tls.to_s,
        :user_name            => "#{smtp_settings.smtp_user}",
        :password             => "#{smtp_settings.smtp_pass}",
        :authentication       => "#{smtp_settings.smtp_auth_type.to_s}", 
        :domain               => "localhost.localdomain"
      }
    }
  else
    Pony.options = {
      :via => :smtp,
      :via_options => {
        :address              => "#{smtp_server}",
        :port                 => "#{smtp_port}",
        :enable_starttls_auto => false
      }
    }
  end

  Pony.mail :to => recipient,
            :from => smtp_settings.smtp_user,
            :subject => sub,
            :body => msg
end
        
