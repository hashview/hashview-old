# encoding: utf-8
class HashView < Sinatra::Application
  get '/' do
    @users = User.all
    if @users.empty?
      redirect to('/register')
    elsif !validSession?
      redirect to('/login')
    else
      redirect to('/home')
    end
  end
end
