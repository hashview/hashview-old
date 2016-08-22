require 'sinatra'
require './helpers/sinatra_ssl.rb'
require 'haml'
require 'dm-sqlite-adapter'
require 'data_mapper'
require './model/master.rb'
require 'json'
require 'redis'
require 'resque'
require './jobs/jobq.rb'
require './helpers/hash_importer'

set :bind, '0.0.0.0'
set :environment, :development
# set :environment, :production

# Check to see if SSL cert is present, if not generate
if !File.exist?('cert/server.crt')
  # Generate Cert
  system('openssl req -x509 -nodes -days 365 -newkey RSA:2048 -subj "/CN=US/ST=Minnesota/L=Duluth/O=potatoFactory/CN=hashview" -keyout cert/server.key -out cert/server.crt')
end

set :ssl_certificate, 'cert/server.crt'
set :ssl_key, 'cert/server.key'
enable :sessions

redis = Redis.new

# to start the resque web queue run the following from the command prompt:
# resque-web

# to start the rake task do: TERM_CHILD=1 QUEUE=* rake resque:work
# ^^^ should probably make an upstart for that

get '/login' do
  @users = User.all
  if @users.empty?
    redirect('/register')
  else
    haml :login
  end
end

## We use a persistent session table, one session per user; no end date
get '/logout' do
  if session[:session_id]
    sess = Sessions.first(:session_key => session[:session_id])
    if sess
      sess.destroy
    end
  end
  redirect to('/')
end

post '/login' do
  @user = User.first(:username => params[:username])

  if @user
    usern = User.authenticate(params['username'], params['password'])

    # if usern and session[:session_id]
    if !usern.nil?
      # only delete session if one exists
      if session[:session_id]
        # replace the session in the session table
        # TODO : This needs an expiration, session fixation
        @del_session = Sessions.first(:username => "#{usern}")
        @del_session.destroy if @del_session
      end
      # Create new session
      @curr_session = Sessions.create(:username => "#{usern}", :session_key => "#{session[:session_id]}")
      @curr_session.save

      redirect to('/home')
    end
  else
    redirect to('/not_authorized')
  end
end

get '/protected' do
  redirect to('/') if !valid_session?
  return 'This is a protected page, you must be logged in.'
end

get '/not_authorized' do
  return 'You are not authorized.'
end

post '/register' do
  # validate that no other user account exists
  @users = User.all
  if @users.empty?
    if params[:password] != params[:confirm]
      return 'Passwords do not match'
    else
      new_user = User.new
      new_user.username = params[:username]
      new_user.password = params[:password]
      new_user.admin = 't'
      new_user.save
    end
  else
    user = User.new
    user.username = params[:username]
    user.password = params[:password]
    user.type = params[:type]
    user.auth_type = params[:auth_type]
    user.save
  end
  redirect to('/home')
end


get '/' do
  @users = User.all
  if @users.empty?
    redirect to("/register")
  elsif !valid_session?
    redirect to("/login")
  else
    redirect to('/home')
  end
end

# dashboard
get '/home' do
  redirect to('/') if !valid_session?
  @results = `ps awwux | grep -i Hashcat | egrep -v "(grep|screen|SCREEN|resque|^$)" | grep -v sudo`
  @targets = Targets.all(:cracked => 1)
  @jobs = Jobs.all
  @jobtasks = Jobtasks.all
  @tasks = Tasks.all
  @recentlycracked = Targets.all(:limit => 10, :cracked => 1, :order => [:updated_at.desc])
  
  # status
  # this cmd requires a sudo TODO:this isnt working due to X env
  # username   ALL=(ALL) NOPASSWD: /usr/bin/amdconfig --adapter=all --odgt

  # nvidia works without sudo:
  @gpustatus = `nvidia-settings -q \"GPUCoreTemp\" | grep Attribute | grep -v gpu | awk '{print $3,$4}'`
  @gpustatus = @gpustatus.split("\n")
  @gpustat = []
  @gpustatus.each do |line|
    unless line.chomp.empty?
      line = line.delete('.')
      @gpustat << line
    end
  end

  encrypted_dir = '/data/hashes'
  @dir_available = File.directory?(encrypted_dir)
  dict_dir = '/mnt/temp/Dictionaries'
  @dict_available = File.directory?(dict_dir)

  @jobs.each do | j |
    if j.status
      p 'Job ID: ' + j.id.to_s
      @alltargets = Targets.all(:jobid => j.id)
      @crackedtargets = Targets.all(:jobid => j.id, :cracked => 1)
      @alltargets = @alltargets.count
      @crackedtargets = @crackedtargets.count 
      @progress = (@crackedtargets.to_f / @alltargets.to_f) * 100
    else
      @alltargets = 0
      @crackedtargets = 0
      @progress = 0
    end
  end
  p 'ALL TARGETS: ' + @alltargets.to_s
  p 'CRACKED TARGETS: ' + @crackedtargets.to_s
  p 'PROGRESS: ' + @progress.to_s
  # simple (and temporary) statistics
  #@jobs.each do |j|
  #  if j.status
  #    # this nonsense will be replaced in the future with sql reads of the targets table
  #    @crackedtargets = 0
  #    Dir["control/outfiles/hc_cracked_#{j.id}_*"].each do |f|
  #      if File.file?(f)
  #        cracked = `wc -l #{f} | awk '{print $1}' | tr -d '\n'`
  #      else
  #        cracked = '0'
  #      end
  #      @crackedtargets += cracked.to_i
  #    end
  #    @alltargets = `wc -l control/hashes/hashfile_upload_jobid-"#{j.id}"* | awk '{print $1}' | tr -d '\n'`
  #    @progress = @crackedtargets.to_f / @alltargets.to_f * 100
  #  end
  #end

  haml :home
end

get '/register' do
  haml :register
end


##### task controllers #####

get '/task/list' do
  redirect to('/') if !valid_session?

  @tasks = Tasks.all()
  @wordlists = Wordlists.all()

  haml :task_list
end

get '/task/delete/:id' do
  redirect to('/') if !valid_session?

  @task = Tasks.first(:id => params[:id])
  if @task
    @task.destroy
  else
    return 'No such task exists.'
  end

  redirect to('/task/list')
end

get '/task/edit/:id' do
  redirect to('/') if !valid_session?

  return 'Page under contruction.'
end

get '/task/create' do
  redirect to('/') if !valid_session?

  settings = Settings.first

  # TODO present better error msg
  if settings.nil?
    return 'You must define hashcat\'s binary path in global settings first.'
  end

  @rules = []
  # list wordlists that can be used
  Dir.foreach('control/rules/') do |item|
    next if item == '.' || item == '..'
      @rules << item
  end

  @wordlists = Wordlists.all()

  #@wordlists = []
  #Dir.foreach('control/wordlists/') do |item|
  #  next if item == '.' or item == '..'
  #    @wordlists << item
  #end

  haml :task_create
end

post '/task/create' do
  redirect to('/') if !valid_session?

  settings = Settings.first()
  wordlist = Wordlists.first(:id => params[:wordlist])
  puts wordlist.path

  if settings && ! settings.hcbinpath
    return 'No hashcat binary path is defined in global settings.'
  end

  task = Tasks.new
  task.name = params[:name]

  if settings && !settings.hcglobalopts
    task.command = 'sudo ' + settings.hcbinpath + ' '
  else
    task.command = 'sudo ' + settings.hcbinpath + ' ' + settings.hcglobalopts + ' '
  end
  puts params
  if params[:attackmode] == 'dictionary'
    attackmode = 0
  elsif params[:attackmode] == 'bruteforce'
    attackmode = 3
  end

  task.hc_attackmode = attackmode
  task.wl_id = wordlist.id
  task.hc_rule = params[:rule]
  task.save

  redirect to('/task/list')
end

############################

##### job controllers #####

get '/job/list' do
  redirect to('/') if !valid_session?

  @jobs = Jobs.all
  @tasks = Tasks.all
  @jobtasks = Jobtasks.all

  haml :job_list
end

get '/job/delete/:id' do
  redirect to('/') if !valid_session?

  @job = Jobs.first(:id => params[:id])
  if !@job
    return 'No such task exists.'
  else
    @job.destroy
  end

  redirect to('/job/list')
end

get '/job/create' do
  redirect to('/') if !valid_session?

  @tasks = Tasks.all

  # we do this so we can embedded ruby into js easily
  # js handles adding/selecting tasks associated with new job
  taskhashforjs = {}
  @tasks.each do |task|
    taskhashforjs[task.id] = task.name
  end
  @taskhashforjs = taskhashforjs.to_json
  @hashtype = Hash.new
  @hashtype = { 'ntlm' => 1000, 'lm' => 3000 }

  haml :job_edit
end

post '/job/create' do
  redirect to('/') if !valid_session?

  # create new job
  job = Jobs.new
  job.name = params[:name]
  job.hashtype = params[:hashtype]
  job.last_updated_by = get_username
  job.save

  # assign tasks to the job
  assign_tasks_to_job(params[:tasks], job.id)

  redirect to("/job/#{job.id}/upload/hashfile")
end

get '/job/:id/upload/hashfile' do
  redirect to('/') if !valid_session?

  @job = Jobs.first(:id => params[:id])
  if !@job
    return 'No such job exists'
  end
  haml :upload_hashfile
end

post '/job/:id/upload/hashfile' do
  redirect to('/') if !valid_session?

  @job = Jobs.first(:id => params[:id])
  if !@job
    return 'No such job exists'
  end

  # temporarily save file for testing
  hash = rand(36**8).to_s(36)
  hashfile = "control/hashes/hashfile_upload_jobid-#{@job.id}-#{hash}.txt"
  
  # Parse uploaded file into an array
  hashArray = Array.new
  wholeFileAsStringObject = params[:file][:tempfile].read
  File.open(hashfile, 'w') { |f| f.write(wholeFileAsStringObject) }
  wholeFileAsStringObject.each_line do |line|
    hashArray << line
  end

  # save location of tmp hash file
  @job.targetfile = hashfile
  @job.save

  redirect to("/job/#{@job.id}/upload/verify_filetype/#{hash}")
end

get '/job/:id/upload/verify_filetype/:hash' do
  redirect to('/') if !valid_session?

  @filetypes = detect_hashfile_type("control/hashes/hashfile_upload_jobid-#{params[:id]}-#{params[:hash]}.txt")
  @job = Jobs.first(:id => params[:id])
  haml :verify_filetypes

end

post '/job/:id/upload/verify_filetype' do
  redirect to('/') if !valid_session?

  filetype = params[:filetype]
  hash = params[:hash]

  redirect to("/job/#{params[:id]}/upload/verify_hashtype/#{hash}/#{filetype}")
end

get '/job/:id/upload/verify_hashtype/:hash/:filetype' do
  redirect to('/') if !valid_session?

  @hashtypes = detect_hash_type("control/hashes/hashfile_upload_jobid-#{params[:id]}-#{params[:hash]}.txt", params[:filetype])
  @job = Jobs.first(:id => params[:id])
  haml :verify_hashtypes

end

post '/job/:id/upload/verify_hashtype' do
  redirect to('/') if !valid_session?

  filetype = params[:filetype]
  hash = params[:hash]
  hashtype = params[:hashtype]

  hashfile = "control/hashes/hashfile_upload_jobid-#{params[:id]}-#{params[:hash]}.txt"

  hashArray = []
  File.open(hashfile, 'r').each do | line |
      hashArray << line
  end

  # we do this to speed up the inserts for large hash imports
  # http://www.sqlite.org/faq.html#q19
  # for some reason this doesnt persist so it is placed here, closest to the commits/inserts
  adapter = DataMapper::repository(:default).adapter
  adapter.select("PRAGMA synchronous = OFF;")

  if not import_hash(hashArray, params[:id], filetype, hashtype)
    return "Error importing hash"  # need to better handle errors
  end

  # Delete file, no longer needed
  File.delete(hashfile)

  redirect to('/job/list')
end

get '/job/edit/:id' do
  redirect to('/') if !valid_session?

  @job = Jobs.first(:id => params[:id])
  if !@job
    return 'No such job exists.'
  else
    @tasks = Tasks.all
    @jobtasks = Jobtasks.all(:job_id => params[:id])
  end

  # we do this so we can embedded ruby into js easily
  # js handles adding/selecting tasks associated with new job
  taskhashforjs = {}
  @tasks.each do |task|
    taskhashforjs[task.id] = task.name
  end
  @taskhashforjs = taskhashforjs.to_json

  haml :job_edit
end

post '/job/edit/:id' do
  redirect to('/') if !valid_session?

  values = request.POST

  @job = Jobs.first(:id => params[:id])
  if !@job
    return 'No such job exists.'
  else
    # update job
    # assign tasks to the job before
    p values
    if values["tasks"] != nil
      assign_tasks_to_job(params[:tasks], @job.id)
      values.delete("tasks")
    end
    @job.update(values)

  end

  redirect to('/job/list')
end

get '/job/start/:id' do
  redirect to('/') if !valid_session?

  tasks = []
  @job = Jobs.first(:id => params[:id])
  if !@job
    return 'No such job exists.'
  else
    @jobtasks = Jobtasks.all(:job_id => params[:id])
    if !@jobtasks
      return 'This job has no tasks to run.'
    else
      @jobtasks.each do |jt|
        tasks << Tasks.first(:id => jt.task_id)
      end
    end
  end

  tasks.each do |task|
    jt = Jobtasks.first(:task_id => task.id, :job_id => @job.id)
    # do not start tasks if they have already been completed.
    # set all other tasks to status of queued
    if not jt.status == "Completed"
      # set jobtask status to queued
      jt.status = "Queued"
      jt.save
      # toggle the job status to run
      @job.status = 1
      @job.save
      cmd = build_crack_cmd(@job.id, task.id)
      cmd = cmd + ' | tee -a control/outfiles/hcoutput_' + @job.id.to_s + '.txt'
      p 'ENQUE CMD: ' + cmd
      Resque.enqueue(Jobq, jt.id, cmd)
    end
  end

  if !@job.status
    return 'All tasks for this job have been completed. To prevent overwriting your results, you will need to create a new job with the same tasks in order to rerun the job.'
  end

  redirect to('/job/list')
end

get '/job/queue' do
  redirect to('/') if !valid_session?
  if is_development?
    redirect to('http://192.168.15.244:5678')
  else
    return redis.keys
  end
end

get '/job/stop/:id' do
  redirect to("/") if !valid_session?

  tasks = []
  @job = Jobs.first(:id => params[:id])
  if !@job
    return 'No such job exists.'
  else
    @jobtasks = Jobtasks.all(:job_id => params[:id])
    if !@jobtasks
      return 'This job has no tasks to stop.'
    else
      @jobtasks.each do |jt|
        tasks << Tasks.first(:id => jt.task_id)
      end
    end
  end

  @job.status = 0
  @job.save

  tasks.each do |task|
    jt = Jobtasks.first(:task_id => task.id, :job_id => @job.id)
    # do not stop tasks if they have already been completed.
    # set all other tasks to status of Canceled
    if not jt.status == 'Completed'
      jt.status = 'Canceled'
      jt.save
      #cmd = task.command + ' | tee -a control/outfiles/hcoutput_' + @job.id.to_s + '.txt'
      cmd = build_crack_cmd(@job.id, task.id)
      cmd = cmd + ' | tee -a control/outfiles/hcoutput_' + @job.id.to_s + '.txt'
      puts 'STOP CMD: ' + cmd
      Resque::Job.destroy('hashcat', Jobq, jt.id, cmd)
    end
  end

  redirect to('/job/list')
end

get '/process/kill/:id' do
  redirect to("/") if !valid_session?

  @result = `sudo kill -9 #{params[:id]}`
  p @result
  redirect to('/home')
end

############################

##### job controllers #####

get '/job/:jobid/task/delete/:jobtaskid' do
  redirect to('/') if !valid_session?

  @job = Jobs.first(:id => params[:jobid])
  if !@job
    return 'No such job exists.'
  else
    @jobtask = Jobtasks.first(:id => params[:jobtaskid])
    @jobtask.destroy
  end

  redirect to("/job/edit/#{@job.id}")
end

############################

##### Global Settings ######

get '/settings' do
  redirect to('/') if !valid_session?

  @settings = Settings.first

  haml :global_settings
end

post '/settings' do
  redirect to('/') if !valid_session?

  values = request.POST

  @settings = Settings.first()

  if @settings == nil
    # create settings for the first time
    @newsettings = Settings.create(values)
    @newsettings.save
  else
    # update settings
  @settings.update(values)
  end

  redirect to('/settings')
end

############################

##### Downloads ############

get '/download/cracked/:jobid' do
  redirect to('/') if !valid_session?

  # Write temp output file
  jobs = Jobs.first(:id => params[:jobid])
  fileName = 'control/outfiles/found_' + params[:jobid].to_s + '.txt'
  crack_results = Targets.all(:jobid => params[:jobid], :cracked => true)

  File.open(fileName, 'w') do |f|
    crack_results.each do |entry|
      line = entry.username + ':' + entry.originalhash + ':' + entry.plaintext
      f.puts line
    end
  end
  save_name = 'cracked_values_ ' + jobs.name.to_s.tr(' ', '_') + '.txt'
  send_file fileName, :filename => save_name, :type => 'Application/octet-stream'
  redirect to('/job/list')
end

get '/download/stats/:jobid' do
  redirect to('/') unless valid_session?

  jobs = Jobs.first(:id => params[:jobid])

  # This could be changed into a prepared statment
  # This could also be put into a helper
  crack_results = Targets.all(:jobid => params[:jobid], :cracked => true)
  @password_frequency = Hash.new(0)
  @password_length = Hash.new(0)
  crack_results.each do |entry|
   password = entry.plaintext.to_s
   password.delete!("\n")
   @password_frequency[password] += 1
   @password_length[password.length] += 1
  end

  file_name = 'control/outfiles/stats' + params[:jobid].to_s + '.txt' 

  File.open(file_name, 'w') do |f|

    # Top 10 passwords
    f.puts 'Top 10 passwords'
    f.puts '================'
    @password_frequency_sorted = Hash[@password_frequency.sort_by {|k,v| v}.reverse[0..10]]
    @password_frequency_sorted.each do |key, value|
      f.puts value.to_s + ":" +  key.to_s
    end

    # Top Base words

    # Top 10 password lengths
    f.puts "\n\n\n"
    f.puts 'Top 10 password lengths'
    f.puts '======================='
    f.puts 'Char length: Counts'
    @password_length_sorted = Hash[@password_length.sort_by {|k,v| k.to_i}[0..10]]
    @password_length_sorted.each do |key, value|
      f.puts key.to_s + ":" + value.to_s
    end

    # Password reuse based off of hashes
  end
  save_name = 'cracked_stats_' + jobs.name.to_s.tr(' ', '_') + '.txt'
  send_file file_name, :filename => save_name, :type => 'Application/octet-stream'

  redirect to('/job/list')
end

############################

##### Word Lists ###########

get '/wordlist/list' do
  redirect to("/") if not valid_session?

  @wordlists = Wordlists.all()

  haml :wordlist_list

end

get '/wordlist/add' do
  redirect to('/') if not valid_session?
  haml :wordlist_add
end

get '/wordlist/delete/:id' do
  redirect to("/") if not valid_session?

  @wordlist = Wordlists.first(:id => params[:id])
  if not @wordlist
    return "no such wordlist exists"
  else
    # remove from filesystem
    File.delete(@wordlist.path)

    # delete from db
    @wordlist.destroy
  end
  redirect to('/wordlist/list')

end

post '/wordlist/upload/' do
  redirect to("/") if not valid_session?

  # require param name && file
  if params[:name].size == 0
    return "File Name Required"
  end

  # Replace white space with underscore.  We need more filtering here too
  uploadname = params[:name]
  uploadname = uploadname.downcase.tr(" ", "_")

  # Change to date/time ?
  rand_str = rand(36**36).to_s(36)

  # Save to file
  filename = "control/wordlists/wordlist-#{uploadname}-#{rand_str}.txt"
  File.open(filename, 'wb') {|f| f.write(params[:file][:tempfile].read) }

  # Identify how many lines/enteries there are
  size = File.foreach(filename).inject(0){|c, line| c+1}

  wordlist = Wordlists.new
  wordlist.name = uploadname # what XSS?
  wordlist.path = filename
  wordlist.size = size
  wordlist.save

  redirect to('/wordlist/list')
end

############################

##### Analysis #############
get '/analysis' do
  return 'Analysis page.'
end

get '/search' do
   haml :search
end

post '/search' do

    key = params[:hash]
    @output = redis.hscan(key, 0)
    haml :search_post
     
end

post '/search_ajax' do
    
    key = params[:hash]
    output = redis.hscan(key, 0)
    return output.to_json
    
end

get '/statistics' do
  return 'Statistics page.'
end

# Helper Functions

# Are we in development mode?
def is_development?
  return Sinatra::Base.development?
end

# Return if the user has a valid session or not
def valid_session?
  return Sessions.is_valid?(session[:session_id])
end

# Get the current users, username
def get_username
  return Sessions.get_username(session[:session_id])
end

# Check if the user is an administrator
def is_administrator?
  return true if Sessions.type(session[:session_id])
end

# this function builds the main hashcat cmd we use to crack. this should be moved to a helper script soon
def build_crack_cmd(jobid, taskid)
  # order of opterations -m hashtype -a attackmode is dictionary? set wordlist, set rules if exist file/hash
  settings = Settings.first
  hcbinpath = settings.hcbinpath
  maxtasktime = settings.maxtasktime
  @task = Tasks.first(:id => taskid)
  @job = Jobs.first(:id => jobid)
  @targets = Targets.first(:jobid => jobid)
  hashtype = @targets.hashtype.to_s
  attackmode = @task.hc_attackmode.to_s
  wordlist = Wordlists.first(:id => @task.wl_id)

  target_file = 'control/hashes/hashfile_' + jobid.to_s + '_' + taskid.to_s + '.txt'

  if attackmode == "3"
    cmd = "sudo " + hcbinpath + " -m " + hashtype + " --potfile-disable" + " --runtime=" + maxtasktime + " --outfile-format 3 " + " --outfile " + "control/outfiles/hc_cracked_" + @job.id.to_s + "_" + @task.id.to_s + ".txt " + " -a " + attackmode + " " + target_file
  elsif attackmode == "0"
    if @task.hc_rule == "none"
      cmd = "sudo " + hcbinpath + " -m " + hashtype + " --potfile-disable" + " --outfile-format 3 " + " --outfile " + "control/outfiles/hc_cracked_" + @job.id.to_s + "_" + @task.id.to_s + ".txt " + target_file + " " + wordlist.path
    else
      cmd = "sudo " + hcbinpath + " -m " + hashtype + " --potfile-disable" + " --outfile-format 3 " + " --outfile " + "control/outfiles/hc_cracked_" + @job.id.to_s + "_" + @task.id.to_s + ".txt " +  " -r " + "control/rules/" + @task.hc_rule + " " + target_file + " " + wordlist.path
    end
  end
  p cmd
  return cmd
end

# Check if kraken has a job running
def is_krakenbusy?
  @results = `ps awwux | grep Hashcat | egrep -v "(grep|^$)" | grep -v sudo`
  return true if @results.length > 1
end

def assign_tasks_to_job(tasks, job_id)
  job = Jobs.first(:id => job_id)
  tasks.each do |task_id|
    jobtask = Jobtasks.new
    jobtask.job_id = job_id
    jobtask.task_id = task_id
    jobtask.save
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
    return session[:username]
  end
end
