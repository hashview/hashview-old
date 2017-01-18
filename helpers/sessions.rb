helpers do
  # Return if the user has a valid session or not
  def validSession?
    Sessions.isValid?(session[:session_id])
  end
end
