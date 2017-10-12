# encoding: utf-8
get '/login' do
  @users = User.all
  @settings = Settings.first
  if @users.empty?
    redirect('/register')
  else
    haml :login
  end
end

get '/logout' do
  varWash(params)
  if session[:session_id]
    sess = Sessions.first(session_key: session[:session_id])
    sess.destroy if sess
  end
  redirect to('/')
end

post '/login' do
  varWash(params)
  if !params[:username] || params[:username].nil?
    flash[:error] = 'You must supply a username.'
    redirect to('/login')
  end

  if !params[:password] || params[:password].nil?
    flash[:error] = 'You must supply a password.'
    redirect to('/login')
  end

  @user = User.first(username: params[:username])

  if @user
    usern = User.authenticate(params['username'], params['password'])

    # if usern and session[:session_id]
    unless usern.nil?
      # only delete session if one exists
      if session[:session_id]
        # replace the session in the session table
        # TODO : This needs an expiration, session fixation
        @del_session = Sessions.first(username: usern)
        @del_session.destroy if @del_session
      end
      # Create new session
      @curr_session = Sessions.create(username: usern, session_key: session[:session_id])
      @curr_session.save

      redirect to('/home')
    end
    flash[:error] = 'Invalid credentials.'
    redirect to('/login')
  else
    flash[:error] = 'Invalid credentials.'
    redirect to('/login')
  end
end

get '/protected' do
  return 'This is a protected page, you must be logged in.'
end

get '/not_authorized' do
  return 'You are not authorized.'
end
