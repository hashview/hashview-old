require 'sinatra'

require './helpers/sinatra_ssl.rb'

# we default to production env b/c i want to
if ENV['RACK_ENV'].nil?
  set :environment, :production
  ENV['RACK_ENV'] = 'production'
end

require 'sinatra/flash'
require 'haml'
require 'data_mapper'
require './model/master.rb'
require 'json'
require 'redis'
require 'resque'
require './jobs/jobq.rb'
require './helpers/hash_importer'
require './helpers/hc_stdout_parser.rb'
require './helpers/email.rb'
require 'pony'

set :bind, '0.0.0.0'

# Check to see if SSL cert is present, if not generate
unless File.exist?('cert/server.crt')
  # Generate Cert
  system('openssl req -x509 -nodes -days 365 -newkey RSA:2048 -subj "/CN=US/ST=Minnesota/L=Duluth/O=potatoFactory/CN=hashview" -keyout cert/server.key -out cert/server.crt')
end

set :ssl_certificate, 'cert/server.crt'
set :ssl_key, 'cert/server.key'
enable :sessions

#redis = Redis.new

# validate every session
before /^(?!\/(login|register|logout))/ do
  if !validSession?
    redirect to('/login')
  else
    settings = Settings.first
    if (settings && settings.hcbinpath.nil?) || settings.nil?
      flash[:warning] = "Annoying alert! You need to define hashcat\'s binary path in settings first. Do so <a href=/settings>HERE</a>"
    end
  end
end

get '/login' do
  @users = User.all
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

############################

### Register controllers ###

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

############################

##### Home controllers #####

## Moved to controler/main.rb

############################

### customer controllers ###

## Moved to routes/customers.rb

############################

### Account controllers ####

## Moved to routes/accounts.rb

############################

##### task controllers #####

## Moved to routes/tasks.rb

############################

##### job controllers #####

## Moved to routes/jobs.rb

############################

##### Global Settings ######

## Moved to routes/settings.rb

############################

##### Tests ################

get '/test/email' do

  account = User.first(username: getUsername)
  if account.email.nil? or account.email.empty?
    flash[:error] = 'Current logged on user has no email address associated.'
    redirect to('/settings')
  end

  if ENV['RACK_ENV'] != 'test'
    sendEmail(account.email, "Greetings from hashview", "This is a test message from hashview")
  end

  flash[:success] = 'Email sent.'

  redirect to('/settings')
end

############################

##### Downloads ############

## Moved to routes/download.rb

############################

##### Word Lists ###########

## moved to routes/wordlists.rb

############################

##### Hash Lists ###########

## moved to routes/hashlists.rb

############################

##### Analysis #############

## Moved to routes/analytics.rb

############################

##### search ###############

## Moved to routes/search

############################

# Helper Functions

# Are we in development mode?
def isDevelopment?
  Sinatra::Base.development?
end

# Return if the user has a valid session or not
def validSession?
  Sessions.isValid?(session[:session_id])
end

# Get the current users, username
def getUsername
  Sessions.getUsername(session[:session_id])
end

# Check if the user is an administrator
def isAdministrator?
  return true if Sessions.type(session[:session_id])
end

# this function builds the main hashcat cmd we use to crack. this should be moved to a helper script soon
def buildCrackCmd(job_id, task_id)
  # order of opterations -m hashtype -a attackmode is dictionary? set wordlist, set rules if exist file/hash
  settings = Settings.first
  hcbinpath = settings.hcbinpath
  maxtasktime = settings.maxtasktime
  @task = Tasks.first(id: task_id)
  @job = Jobs.first(id: job_id)
  hashfile_id = @job.hashfile_id
  hash_id = Hashfilehashes.first(hashfile_id: hashfile_id).hash_id
  hashtype = Hashes.first(id: hash_id).hashtype.to_s

  attackmode = @task.hc_attackmode.to_s
  mask = @task.hc_mask

  if attackmode == 'combinator'
    wordlist_list = @task.wl_id
    @wordlist_list_elements = wordlist_list.split(',')
    wordlist_one = Wordlists.first(id: @wordlist_list_elements[0])
    wordlist_two = Wordlists.first(id: @wordlist_list_elements[1])
  else
    wordlist = Wordlists.first(id: @task.wl_id)
  end

  target_file = 'control/hashes/hashfile_' + job_id.to_s + '_' + task_id.to_s + '.txt'

  # we assign and write output file before hashcat.
  # if hashcat creates its own output it does so with
  # elvated permissions and we wont be able to read it
  crack_file = 'control/outfiles/hc_cracked_' + @job.id.to_s + '_' + @task.id.to_s + '.txt'
  File.open(crack_file, 'w')

  if attackmode == 'bruteforce'
    cmd = hcbinpath + ' -m ' + hashtype + ' --potfile-disable' + ' --status-timer=15' + ' --runtime=' + maxtasktime + ' --outfile-format 3 ' + ' --outfile ' + crack_file + ' ' + ' -a 3 ' + target_file + ' -w 3'
  elsif attackmode == 'maskmode'
    cmd = hcbinpath + ' -m ' + hashtype + ' --potfile-disable' + ' --status-timer=15' + ' --outfile-format 3 ' + ' --outfile ' + crack_file + ' ' + ' -a 3 ' + target_file + ' ' + mask + ' -w 3'
  elsif attackmode == 'dictionary'
    if @task.hc_rule == 'none'
      cmd = hcbinpath + ' -m ' + hashtype + ' --potfile-disable' + ' --status-timer=15' + ' --outfile-format 3 ' + ' --outfile ' + crack_file + ' ' + target_file + ' ' + wordlist.path + ' -w 3'
    else
      cmd = hcbinpath + ' -m ' + hashtype + ' --potfile-disable' + ' --status-timer=15' + ' --outfile-format 3 ' + ' --outfile ' + crack_file + ' ' + ' -r ' + 'control/rules/' + @task.hc_rule + ' ' + target_file + ' ' + wordlist.path + ' -w 3'
    end
  elsif attackmode == 'combinator'
    cmd = hcbinpath + ' -m ' + hashtype + ' --potfile-disable' + ' --status-timer=15' + '--outfile-format 3 ' + ' --outfile ' + crack_file + ' ' + ' -a 1 ' + target_file + ' ' + wordlist_one.path + ' ' + ' ' + wordlist_two.path + ' ' + @task.hc_rule.to_s + ' -w 3'
  end
  p cmd
  cmd
end

# Check if a job running
def isBusy?
  @results = `ps awwux | grep -i Hashcat | egrep -v "(grep|sudo|resque|^$)"`
  return true if @results.length > 1
end

def assignTasksToJob(tasks, job_id)
  tasks.each do |task_id|
    jobtask = Jobtasks.new
    jobtask.job_id = job_id
    jobtask.task_id = task_id
    jobtask.save
  end
end

def isOldVersion()
  begin
    if Targets.all
      return true
    else
      return false
    end
  rescue
    # we really need a better upgrade process
    return false
  end
end

helpers do
  def login?
    if session[:username].nil?
      return false
    else
      return true
    end
  end

  def username
    session[:username]
  end

  # Take you to the var wash baby
  def varWash(params)
    params.keys.each do |key|
      if params[key].is_a?(String)
        params[key] = cleanString(params[key])
      end
      if params[key].is_a?(Array)
        params[key] = cleanArray(params[key])
      end
    end
  end

  def cleanString(text)
    return text.gsub(/[<>'"()\/\\]*/i, '') unless text.nil?
  end

  def cleanArray(array)
    clean_array = []
    array.each do |entry|
      clean_array.push(cleanString(entry))
    end
    return clean_array
  end
end
