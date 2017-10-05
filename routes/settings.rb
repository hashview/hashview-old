# encoding: utf-8
get '/settings' do

  @hc_settings = HashcatSettings.first
  @hub_settings = HubSettings.first

  @themes = %w(Light Dark Slate Flat Superhero Solar)

  if @hc_settings.nil?
    @hc_settings = HashcatSettings.create # This shouldn't be needed
    @hc_settings = HashcatSettings.first

  end

  @settings = Settings.first
  if @settings.nil?
    @settings = Settings.create # This too shouldn't be needed
    @settings = Settings.first
  end

  if @hub_settings.nil?
    @hub_settings = HubSettings.create
    @hub_settings = HubSettings.first

    if @hub_settings.uuid.nil?
      p 'Generating new UUID'
      uuid = SecureRandom.hex(10)
      # Add hyphens, (i am ashamed at how dumb this is)
      uuid.insert(15, '-')
      uuid.insert(10, '-')
      uuid.insert(5, '-')
      @hub_settings.uuid = uuid
      @hub_settings.save
    end

  end
  if @hub_settings.status == 'registered'
    if @hub_settings.uuid and @hub_settings.auth_key
      hub_response = Hub.statusAuth
      hub_response = JSON.parse(hub_response)
      if hub_response['status'] == '403'
        flash[:error] = 'Invalid Authentication to Hub, check UUID.'
      elsif hub_response['status'] == '200'
        @hub_settings.save
        @hub_settings = HubSettings.first
      end
    end
  end
  @auth_types = %w(None Plain Login cram_md5)

  # get hcbinpath (stored in config file vs db)
  @hc_binpath = JSON.parse(File.read('config/agent_config.json'))['hc_binary_path']
 
  haml :global_settings
end
  
post '/settings' do
  if params[:form_id] == '1' # Hashcat Settings

    # Declare our db object first so that we can save values along the way instead of at the end
    hc_settings = HashcatSettings.first

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
    params[:gpu_temp_disable] == 'on' ? hc_settings.gpu_temp_disable = '1' : hc_settings.gpu_temp_disable = '0'

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
    params[:hc_force] == 'on' ? hc_settings.hc_force = 1 : hc_settings.hc_force = 0

    hc_settings.save

  elsif params[:form_id] == '2' # Email
    settings = Settings.first

    params[:smtp_use_tls] == 'on' ? params[:smtp_use_tls] = '1' : params[:smtp_use_tls] = '0'

    settings.smtp_server = params[:smtp_server] unless params[:smtp_server].nil? || params[:smtp_server].empty?
    settings.smtp_sender = params[:smtp_sender] unless params[:smtp_sender].nil? || params[:smtp_sender].empty?
    settings.smtp_auth_type = params[:smtp_auth_type] unless params[:smtp_auth_type].nil? || params[:smtp_auth_type].empty?
    settings.smtp_use_tls = params[:smtp_use_tls] unless params[:smtp_use_tls].nil? || params[:smtp_use_tls].empty?
    settings.smtp_user = params[:smtp_user] unless params[:smtp_user].nil? || params[:smtp_user].empty?
    settings.smtp_pass = params[:smtp_pass] unless params[:smtp_pass].nil? || params[:smtp_pass].empty?
    settings.save

  elsif params[:form_id] == '3' # UI Settings
    settings = Settings.first
    settings.ui_themes = params[:ui_themes] unless params[:ui_themes].nil? || params[:ui_themes].empty?
    settings.save

  elsif params[:form_id] == '4' # Distributed settings
    settings = Settings.first
    # distributed settings
    if params[:chunk_size]
      settings.chunk_size = params[:chunk_size].to_i
      settings.save
    end

  elsif params[:form_id] == '5' # Hub

    if params[:email].nil? || params[:email].empty?
      flash[:error] = 'You must provide an email address.'
      redirect to('/settings')
    end

    hub_settings = HubSettings.first
    hub_settings.email = params[:email] unless params[:email].nil? || params[:email].empty?
    hub_settings.uuid = params[:uuid] unless params[:uuid].nil? || params[:uuid].empty?
    hub_settings.save

    if hub_settings.status != 'registered'
      hub_response = Hub.register('new')
      hub_response = JSON.parse(hub_response)
      if hub_response['status'] == '200'
        hub_settings = HubSettings.first
        hub_settings.auth_key = hub_response['auth_key']
        hub_settings.status = 'registered'
        hub_settings.save
        flash[:success] = 'Hub registration success.'
      else
        flash[:error] = 'Hub registration failed.'
      end
    else
      hub_response = Hub.register('remove')
      hub_response = JSON.parse(hub_response)
      if hub_response['status'] == '200'
        hub_settings = HubSettings.first
        hub_settings.destroy
        flash[:success] = 'Successfully unregistered.'
      else
        flash[:error] = 'Failed to unregister.'
      end
    end
    redirect to('/settings')
  end

  flash[:success] = 'Settings updated successfully.'
  redirect to('/settings')
end

get '/test/email' do

  account = User.first(username: getUsername)
  if account.email.nil? || account.email.empty?
    flash[:error] = 'Current logged on user has no email address associated.'
    redirect to('/settings')
  end

  if ENV['RACK_ENV'] != 'test'
    sendEmail(account.email, 'Greetings from hashview', 'This is a test message from hashview')
  end

  flash[:success] = 'Email sent.'

  redirect to('/settings')
end