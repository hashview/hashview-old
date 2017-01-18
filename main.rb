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


# Check to see if SSL cert is present, if not generate
# Moved to helpers/sinatra_ssl

#redis = Redis.new

# validate every session

## moved to hashview.rb

## Moved to routes/login

############################

### Register controllers ###

## moved to routes/register

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

## Moved to helpers/build_crack_cmd

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

end
