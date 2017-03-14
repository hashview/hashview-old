# encoding: utf-8
get '/accounts/list' do
  @users = User.all
  haml :account_list
end

get '/accounts/create' do
  haml :account_edit
end

post '/accounts/create' do
  varWash(params)

  if params[:username].nil? || params[:username].empty?
    flash[:error] = 'You must have username.'
    redirect to('/accounts/create')
  end

  if params[:password].nil? || params[:password].empty?
    flash[:error] = 'You must have a password.'
    redirect to('/accounts/create')
  end

  if params[:confirm].nil? || params[:confirm].empty?
    flash[:error] = 'You must have a password.'
    redirect to('/accounts/create')
  end

  # validate that no other user account exists
  @users = User.all(username: params[:username])
  if @users.empty?
    if params[:password] != params[:confirm]
      flash[:error] = 'Passwords do not match'
      redirect to('/accounts/create')
    else
      new_user = User.new
      new_user.username = params[:username]
      new_user.password = params[:password]
      new_user.email = params[:email] unless params[:email].nil? || params[:email].empty?
      new_user.admin = 't'
      new_user.save
    end
  else
    flash[:error] = 'User account already exists.'
    redirect to('/accounts/create')
  end
  redirect to('/accounts/list')
end

get '/accounts/edit/:account_id' do
  varWash(params)

  @user = User.first(id: params[:account_id])

  haml :account_edit
end

post '/accounts/save' do
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
  user.username = params[:username]
  user.password = params[:password] unless params[:password].nil? || params[:password].empty?
  user.email = params[:email] unless params[:email].nil? || params[:email].empty?
  user.save
  
  flash[:success] = 'Account successfuly updated.'

  redirect to('/accounts/list')
end

get '/accounts/delete/:id' do
  varWash(params)

  @user = User.first(id: params[:id])
  @user.destroy unless @user.nil?

  redirect to('/accounts/list')
end
