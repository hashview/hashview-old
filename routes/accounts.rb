# encoding: utf-8
get '/accounts/list' do
  authorize :application, :admin_access?
  @users = User.all
  haml :account_list
end

get '/accounts/create' do
  authorize :application, :admin_access?
  haml :account_edit
end

post '/accounts/create' do
  authorize :application, :admin_access?
  varWash(params)

  if params[:confirm].nil? || params[:confirm].empty? && !params[:mfa]
    flash[:error] = 'You must have a password.'
    redirect to('/accounts/create')
  end

  if params[:password] != params[:confirm]
    flash[:error] = 'Passwords do not match'
    redirect to('/accounts/create')
  else
    new_user = User.new(
      username: params[:username],
      password: params[:password],
      email: params[:email],
      admin: 't',
      mfa: params[:mfa] ? 't' : 'f',
      auth_secret:  params[:mfa] ? ROTP::Base32.random_base32 : ''
    )
    new_user.id = User.last[:id].to_i + 1
    # sequel does not understand composite primary
    # keys, and cant figure out which autoincrements

    if new_user.valid?
      new_user.save
    else
      flash[:error] = new_user.errors.full_messages.first.capitalize
      redirect to('/accounts/create')
    end
  end
  redirect to('/accounts/list')
end

get '/accounts/edit/:account_id' do
  authorize :application, :admin_access?
  varWash(params)

  @user = User.first(id: params[:account_id])
  data = Rack::Utils.escape(ROTP::TOTP.new(@user.auth_secret).provisioning_uri(@user.username))
  @otp = "https://chart.googleapis.​com/chart?chs=200x200&chld=M|0&cht=qr&chl=#{data}"
  haml :account_edit
end

post '/accounts/save' do
  authorize :application, :admin_access?
  varWash(params)

  if params[:account_id].nil? || params[:account_id].empty?
    flash[:error] = 'Invalid account.'
    redirect to('/accounts/list')
  end

  if params[:username].nil? || params[:username].empty?
    flash[:error] = 'Invalid username.'
    redirect to("/accounts/edit/#{params[:account_id]}")
  end

  if params[:password] != params[:confirm]
    flash[:error] = 'Passwords do not match.'
    redirect to("/accounts/edit/#{params[:account_id]}")
  end

  user = User.first(id: params[:account_id])
  user.admin = (params[:admin] == 'on' ? 't' : 'f')
  user.username = params[:username]
  user.password = params[:password] unless params[:password].nil? || params[:password].empty?
  user.email = params[:email] unless params[:email].nil? || params[:email].empty?
  user.admin = 't' if params[:admin] == 'on'
  user.auth_secret = (params[:mfa] && user.auth_secret == '') ? ROTP::Base32.random_base32 : ''
  user.mfa = params[:mfa] ? 't' : 'f'
  if user.valid?
    user.save
    flash[:success] = 'Account successfully updated.'
    redirect to('/accounts/list')
  else
    flash[:error] = user.errors.full_messages.first.capitalize
    redirect to("/accounts/edit/#{params[:account_id]}")
  end
end

get '/accounts/me' do
  varWash(params)

  @user = current_user

  data = Rack::Utils.escape(ROTP::TOTP.new(@user.auth_secret).provisioning_uri(@user.username))
  @otp = "https://chart.googleapis.com/chart?chs=200x200&chld=M|0&cht=qr&chl=#{data}"
  haml :account_me
end

post '/accounts/me' do
  varWash(params)

  if params[:password] != params[:confirm]
    flash[:error] = 'Passwords do not match.'
    redirect to('/accounts/me')
  end

  user = current_user
  user.password = params[:password] unless params[:password].nil? || params[:password].empty?
  user.email = params[:email] unless params[:email].nil? || params[:email].empty?
  user.auth_secret = (params[:mfa] && user.auth_secret == '') ? ROTP::Base32.random_base32 : ''
  user.mfa = params[:mfa] ? 't' : 'f'
  if user.valid?
    user.save
    flash[:success] = 'Account successfully updated.'
  else
    flash[:error] = user.errors.full_messages.first.capitalize
  end
  redirect to('/accounts/me')
end

get '/accounts/delete/:id' do
  authorize :application, :admin_access?
  varWash(params)

  @user = User.first(id: params[:id])
  @user.destroy unless @user.nil?

  redirect to('/accounts/list')
end
