# encoding: utf-8
get '/settings' do

  @hc_settings = HcSettings.first

  @themes = %w(Light Dark Slate Flat Superhero Solar)

  if @hc_settings.nil?
    @hc_settings = HcSettings.create
    @hc_settings = HcSettings.first

  end

  @settings = Settings.first
  if @settings.nil?
    @settings = Settings.create
    @settings = Settings.first
  end
  @auth_types = %w(None Plain Login cram_md5)
 
  haml :global_settings
end
  
post '/settings' do
  if params[:form_id] == '1' # Hashcat Settings

    # Declare our db object first so that we can save values along the way instead of at the end
    hc_settings = HcSettings.first

    # Hashcat Binary Path Sanity checks
    if params[:hc_binpath].nil? || params[:hc_binpath].empty?
      flash[:error] = 'You must set the path for your hashcat binary.'
      redirect('/settings')
    end

    unless File.file?(params[:hc_binpath])
      flash[:error] = 'Invalid file / path for hashcat binary.'
      redirect('/settings')
    end

    # hcbinpath looks good
    hc_settings.hc_binpath = params[:hc_binpath]

    # Max Task Time Sanity checks
    if params[:max_task_time].nil? || params[:max_task_time].empty?
      flash[:error] = 'You must set a max task time.'
      redirect('/settings')
    end

    if params[:max_task_time] !~ /^\d*$/
      flash[:error] = 'Max Task Time must be a numeric value.'
      redirect('/settings')
    end

    # Max Task time looks good
    hc_settings.max_task_time = params[:max_task_time]

    # Sanity Check for opencl-device-types
    if params[:opencl_device_types]
      if params[:opencl_device_types] == '0' || params[:opencl_device_types] == '1' || params[:opencl_device_types] == '2' || params[:opencl_device_types] == '3'
        hc_settings.opencl_device_types = params[:opencl_device_types].to_i
      else
        flash[:error] = 'Invalid value for --opencl-device-types'
        redirect('/settings')
      end
    end

    # Sanity check for workload profiles
    if params[:workload_profile]
      if params[:workload_profile] == '0' || params[:workload_profile] == '1' || params[:workload_profile] == '2' || params[:workload_profile] == '3' || params[:workload_profile] == '4'
        hc_settings.workload_profile = params[:workload_profile].to_i
      else
        flash[:error] = 'Invalid value for --workload-profile'
        redirect('/settings')
      end
      if params[:workload_profile] == '4'
        flash[:warning] = 'WARNING: Workload profile set to 4 (insane). This may affect the response time of hashview.'
      end
    end

    # Save gpu temp disable setting
    if params[:gpu_temp_disable] == 'on'
      hc_settings.gpu_temp_disable = '1'
    else
      hc_settings.gpu_temp_disable = '0'
    end

    # Sanity check for gpu temp abort
    if params[:gpu_temp_abort] !~ /^\d*$/
      flash[:error] = 'GPU temperature abort value must be a numeric value.'
      redirect('/settings')
    end

    if params[:gpu_temp_abort] >= '90'
      flash[:warning] = 'WARNING: GPU temperature abort value is greater than 90c'
    end

    hc_settings.gpu_temp_abort = params[:gpu_temp_abort].to_i

    # Sanity check for gpu retain value
    if params[:gpu_temp_retain] !~ /^\d*$/
      flash[:error] = 'GPU temperature retain value must be a numeric value.'
      redirect('/settings')
    end

    if params[:gpu_temp_retain] >= '90'
      flash[:warning] = 'WARNING: GPU temperature retain value is greater than 90c'
    end

    hc_settings.gpu_temp_retain = params[:gpu_temp_retain].to_i

    # Save force settings
    if params[:force] == 'on'
      hc_settings.force = '1'
    else
      hc_settings.force = '0'
    end

    hc_settings.save

  elsif params[:form_id] == '2' || '3' # Email & UI Settings
    settings = Settings.first

    if params[:smtp_use_tls] == 'on'
      params[:smtp_use_tls] = '1'
    else
      params[:smtp_use_tls] = '0'
    end

    settings.smtp_server = params[:smtp_server] unless params[:smtp_server].nil? || params[:smtp_server].empty?
    settings.smtp_sender = params[:smtp_sender] unless params[:smtp_sender].nil? || params[:smtp_sender].empty?
    settings.smtp_auth_type = params[:smtp_auth_type] unless params[:smtp_auth_type].nil? || params[:smtp_auth_type].empty?
    settings.smtp_use_tls = params[:smtp_use_tls] unless params[:smtp_use_tls].nil? || params[:smtp_use_tls].empty?
    settings.smtp_user = params[:smtp_user] unless params[:smtp_user].nil? || params[:smtp_user].empty?
    settings.smtp_pass = params[:smtp_pass] unless params[:smtp_pass].nil? || params[:smtp_pass].empty?
    settings.ui_themes = params[:ui_themes] unless params[:ui_themes].nil? || params[:ui_themes].empty?

    settings.save

  end

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
    sendEmail(account.email, 'Greetings from hashview', 'This is a test message from hashview')
  end

  flash[:success] = 'Email sent.'

  redirect to('/settings')
end

