# encoding: utf-8
get '/settings' do

  @auth_types = %w(None Plain Login cram_md5)

  @themes = %w(Light Dark)

  if @settings && @settings.maxtasktime.nil?
    flash[:info] = 'Max task time must be defined in seconds (86400 is 1 day)'
  end
 
  haml :global_settings
end
  
post '/settings' do
  if params[:form_id] == '1'
    if params[:hcbinpath].nil? || params[:hcbinpath].empty?
      flash[:error] = 'You must set the path for your hashcat binary.'
      redirect('/settings')
    end
  
    if params[:maxtasktime].nil? || params[:maxtasktime].empty?
      flash[:error] = 'You must set a max task time.'
      redirect('/settings')
    end

    # Verify HCBinpath Exists
    unless File.file?(params[:hcbinpath])
      flash[:error] = 'Invalid file / path for hashcat binary.'
      redirect('/settings')
    end
  elsif params[:form_id] == '2'
    if params[:smtp_use_tls] == 'on'
      params[:smtp_use_tls] = '1'
    else
      params[:smtp_use_tls] = '0'
    end
  elsif params[:form_id] == '3'
  end
 
 
  settings = Settings.first

  if settings.nil?
    settings = Settings.create
  end
  
  settings.hcbinpath = params[:hcbinpath] unless params[:hcbinpath].nil? || params[:hcbinpath].empty?
  settings.maxtasktime = params[:maxtasktime] unless params[:maxtasktime].nil? || params[:maxtasktime].empty?
  settings.smtp_server = params[:smtp_server] unless params[:smtp_server].nil? || params[:smtp_server].empty?
  settings.smtp_sender = params[:smtp_sender] unless params[:smtp_sender].nil? || params[:smtp_sender].empty?
  settings.smtp_auth_type = params[:smtp_auth_type] unless params[:smtp_auth_type].nil? || params[:smtp_auth_type].empty?
  settings.smtp_use_tls = params[:smtp_use_tls] unless params[:smtp_use_tls].nil? || params[:smtp_use_tls].empty?
  settings.smtp_user = params[:smtp_user] unless params[:smtp_user].nil? || params[:smtp_user].empty?
  settings.smtp_pass = params[:smtp_pass] unless params[:smtp_pass].nil? || params[:smtp_pass].empty?
  settings.ui_themes = params[:ui_themes] unless params[:ui_themes].nil? || params[:ui_themes].empty?
  settings.save
  
  flash[:success] = 'Settings updated successfully.'

  redirect to('/settings')
end

get '/test/email' do

  account = User.first(username: getUsername)
  if account.email.nil? or account.email.empty?
    flash[:error] = 'Current logged on user has no email address associated.'
    redirect to('/settings')
  end

  if ENV['RACK_ENV'] != 'test'
    sendEmail(account.email, "Greetings from hashview", "This is a test message from hashview")
  end

  flash[:success] = 'Email sent.'

  redirect to('/settings')
end

