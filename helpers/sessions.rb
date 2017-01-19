helpers do
  # Return if the user has a valid session or not
  def validSession?
    Sessions.isValid?(session[:session_id])
  end

  # Get the current users, username
  def getUsername
    Sessions.getUsername(session[:session_id])
  end
end
