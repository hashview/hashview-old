get '/register' do
  @users = User.all
  @settings = Settings.first
  # Prevent registering of multiple admins
  redirect to('/') unless @users.empty?

  haml :register
end

post '/register' do
  varWash(params)

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
      new_user = User.new(
        username: params[:username],
        password: params[:password],
        email: params[:email],
        admin: 't',
        mfa: params[:mfa] ? 't' : 'f',
        auth_secret:  params[:mfa] ? ROTP::Base32.random_base32 : ''
      )
      new_user.id = 1 # since this is the first user
      if new_user.valid?
        new_user.save
        flash[:success] = "User #{params[:username]} created successfully"
      else
        flash[:error] = new_user.errors.full_messages.first.capitalize
        redirect to('/register')
      end
    end
  end

  redirect to('/login')
end
