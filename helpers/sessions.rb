helpers do
  # Return if the user has a valid session or not
  def validSession?
    Sessions.isValid?(session[:session_id])
  end

  # Get the current users, username
  def getUsername
    Sessions.getUsername(session[:session_id])
  end

  def agentAuthorized(uuid)
    auth = Agents.exclude(Sequel.like(:status, 'Pending')).where(:uuid => uuid).first

    auth ? true : false
  end

  def current_session
    Sessions.first(session_key: session[:session_id])
  end

  # Pull current_user to use everywhere
  def current_user
    User.find(username: current_session&.username)
  end
end
