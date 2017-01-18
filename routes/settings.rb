# encoding: utf-8
get '/settings' do
  @settings = Settings.first

  @auth_types = %w(None Plain Login cram_md5)

  if @settings && @settings.maxtasktime.nil?
    flash[:info] = 'Max task time must be defined in seconds (86400 is 1 day)'
  end
 
  haml :global_settings
end
  
post '/settings' do
  if params[:hcbinpath].nil? || params[:hcbinpath].empty?
    flash[:error] = 'You must set the path for your hashcat binary.'
    redirect('/settings')
  end
  
  if params[:maxtasktime].nil? || params[:maxtasktime].empty?
    flash[:error] = 'You must set a max task time.'
    redirect('/settings')
  end
  
  if params[:smtp_use_tls] == 'on'
    params[:smtp_use_tls] = '1'
  else
    params[:smtp_use_tls] = '0'
  end
 
  settings = Settings.first

  if settings.nil?
    settings = Settings.create
  end
  
  settings.hcbinpath = params[:hcbinpath] unless params[:hcbinpath].nil? || params[:hcbinpath].empty?
  settings.maxtasktime = params[:maxtasktime] unless params[:maxtasktime].nil? || params[:maxtasktime].empty?
  settings.smtp_server = params[:smtp_server] unless params[:smtp_server].nil? || params[:smtp_server].nil?
  settings.smtp_auth_type = params[:smtp_auth_type] unless params[:smtp_auth_type].nil? || params[:smtp_auth_type].empty?
  settings.smtp_use_tls = params[:smtp_use_tls] unless params[:smtp_use_tls].nil? || params[:smtp_use_tls].empty?
  settings.smtp_user = params[:smtp_user] unless params[:smtp_user].nil? || params[:smtp_user].empty?
  settings.smtp_pass = params[:smtp_pass] unless params[:smtp_pass].nil? || params[:smtp_pass].empty?
  settings.save
  
  flash[:success] = 'Settings updated successfully.'

  redirect to('/home')
end
