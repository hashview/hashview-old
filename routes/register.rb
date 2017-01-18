get '/register' do
  @users = User.all

  # Prevent registering of multiple admins
  redirect to('/') unless @users.empty?

  haml :register
end

post '/register' do
  varWash(params)
  if !params[:username] || params[:username].nil? || params[:username].empty?
    flash[:error] = 'You must have a username.'
    redirect to('/register')
  end

  if !params[:password] || params[:password].nil? || params[:password].empty?
    flash[:error] = 'You must have a password.'
    redirect to('/register')
  end

  if !params[:confirm] || params[:confirm].nil? || params[:confirm].empty?
    flash[:error] = 'You must have a password.'
    redirect to('/register')
  end

  # validate that no other user account exists
  @users = User.all
  if @users.empty?
    if params[:password] != params[:confirm]
      flash[:error] = 'Passwords do not match.'
      redirect to('/register')
    else
      new_user = User.new
      new_user.username = params[:username]
      new_user.password = params[:password]
      new_user.email = params[:email] unless params[:email].nil? || params[:email].empty?
      new_user.admin = 't'
      new_user.save
      flash[:success] = "User #{params[:username]} created successfully"
    end
  end

  redirect to('/login')
end

