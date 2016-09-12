require 'sinatra'
require './helpers/sinatra_ssl.rb'

# we default to production env b/c i want to
if ENV['RACK_ENV'].nil?
  set :environment, :production
  ENV['RACK_ENV'] = 'production'
end

require 'haml'
require 'data_mapper'
require './model/master.rb'
require 'json'
require 'redis'
require 'resque'
require './jobs/jobq.rb'
require './helpers/hash_importer'
require './helpers/hc_stdout_parser.rb'

set :bind, '0.0.0.0'

# Check to see if SSL cert is present, if not generate
unless File.exist?('cert/server.crt')
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

# validate every session
before /^(?!\/(login|register|logout))/ do
  redirect to('/login') unless validSession?
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
  session[:session_id] = clean(session[:session_id])
  if session[:session_id]
    sess = Sessions.first(session_key: session[:session_id])
    sess.destroy if sess
  end
  redirect to('/')
end

post '/login' do
  return 'You must supply a username.' if !params[:username] || params[:username].nil?
  return 'You must supply a password.' if !params[:password] || params[:password].nil?
  session[:username] = clean(params[:username])
  session[:password] = clean(params[:password])

  @user = User.first(username: params[:username])

  if @user
    usern = User.authenticate(params['username'], params['password'])

    # if usern and session[:session_id]
    unless usern.nil?
      # only delete session if one exists
      if session[:session_id]
        # replace the session in the session table
        # TODO : This needs an expiration, session fixation
        @del_session = Sessions.first(username: "#{usern}")
        @del_session.destroy if @del_session
      end
      # Create new session
      @curr_session = Sessions.create(username: "#{usern}", session_key: "#{session[:session_id]}")
      @curr_session.save

      redirect to('/home')
    end
  else
    redirect to('/not_authorized')
  end
end

get '/protected' do
  return 'This is a protected page, you must be logged in.'
end

get '/not_authorized' do
  return 'You are not authorized.'
end

post '/register' do
  return 'You must have a username.' if !params[:username] || params[:username].nil?
  return 'You must have a password.' if !params[:password] || params[:password].nil?
  return 'You must have a password.' if !params[:confirm] || params[:confirm].nil?

  params[:username] = clean(params[:username])
  params[:password] = clean(params[:password])
  params[:confirm] = clean(params[:confirm])

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
  end
  redirect to('/home')
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

##### Home controllers #####

get '/home' do
  @results = `ps awwux | grep -i Hashcat | egrep -v "(grep|screen|SCREEN|resque|^$)" | grep -v sudo`
  @jobs = Jobs.all
  @jobtasks = Jobtasks.all
  @tasks = Tasks.all
  @recentlycracked = Targets.all(limit: 10, cracked: 1)
  @customers = Customers.all
  @active_jobs = Jobs.first(fields: [:id, :status], status: 'Running')

  # status
  # this cmd requires a sudo TODO:this isnt working due to X env
  # username   ALL=(ALL) NOPASSWD: /usr/bin/amdconfig --adapter=all --odgt

  # nvidia works without sudo:
  @gpustatus = `nvidia-settings -q \"GPUCoreTemp\" | grep Attribute | grep -v gpu | awk '{print $3,$4}'`
  if @gpustatus.empty?
    @gpustatus = `lspci | grep "VGA compatible controller" | cut -d: -f3 | sed 's/\(rev a1\)//g'`
  end
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

  @jobs.each do |j|
    if j.status == 'Running'
      # gather info for statistics
      @alltargets = Targets.count(jobid: j.id)
      @crackedtargets = Targets.count(jobid: j.id, cracked: 1)
      @progress = (@crackedtargets.to_f / @alltargets.to_f) * 100
      # parse a hashcat status file
      @hashcat_status = hashcatParser('control/outfiles/hcoutput_' + j.id.to_s + '.txt')
    end
  end

  haml :home
end

get '/register' do
  haml :register
end

############################

### customer controllers ###

get '/customers/list' do
  @customers = Customers.all
  @total_jobs = []
  @total_hashes = []

  @customers.each do | customer |
    @total_jobs[customer.id] = Jobs.count(customer_id: customer.id)
    @total_hashes[customer.id] = Targets.count(customerid: customer.id)
  end

  haml :customer_list
end

get '/customers/create' do
  haml :customer_edit
end

post '/customers/create' do
  return 'You must provide a Customer Name.' if !params[:name] || params[:name].nil?

  params[:name] = clean(params[:name])
  params[:desc] = clean(params[:desc]) if params[:desc] && !params[:desc].nil?

  customer = Customers.new
  customer.name = params[:name]
  customer.description = params[:desc]
  customer.save

  redirect to('customers/list')
end

get '/customers/edit/:id' do
  @customer = Customers.first(id: params[:id])

  haml :customer_edit
end

post '/customers/edit/:id' do
  return 'You must provide Customer Name.' if !params[:name] || params[:name].nil?

  params[:id] = clean(params[:id]) if params[:id] && !params[:id].nil?
  params[:name] = clean(params[:name])
  params[:desc] = clean(params[:desc]) if params[:desc] && !params[:desc].nil?

  customer = Customers.first(id: params[:id])
  customer.name = params[:name]
  customer.description = params[:desc]
  customer.save

  redirect to('customers/list')
end

get '/customers/delete/:id' do
  params[:id] = clean(params[:id])

  @customer = Customers.first(id: params[:id])
  @customer.destroy unless @customer.nil?

  @jobs = Jobs.all(customer_id: params[:id])
  unless @jobs.nil?
    @jobs.each do |job|
      @jobtasks = Jobtasks.all(job_id: job.id)
      @jobtasks.destroy unless @jobtasks.nil?
    end
    @jobs.destroy unless @jobs.nil?
  end

  @targets = Targets.all(customerid: params[:id])
  @targets.destroy unless @targets.nil?

  redirect to('/customers/list')
end

############################

### Account controllers ####

get '/accounts/list' do
  @users = User.all

  haml :account_list
end

get '/accounts/create' do
  haml :account_edit
end

post '/accounts/create' do
  return 'You must have a username.' if !params[:username] || params[:username].nil?
  return 'You must have a password.' if !params[:password] || params[:password].nil?
  return 'You must have a password.' if !params[:confirm] || params[:confirm].nil?

  params[:username] = clean(params[:username])
  params[:password] = clean(params[:password])
  params[:confirm] = clean(params[:confirm])

  # validate that no other user account exists
  @users = User.all(username: params[:username])
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
    return 'User already exists.'
  end
  redirect to('/accounts/list')
end

get '/accounts/delete/:id' do
  params[:id] = clean(params[:id])

  @user = User.first(id: params[:id])
  @user.destroy unless @user.nil?

  redirect to('/accounts/list')
end

############################

##### task controllers #####

get '/tasks/list' do
  @tasks = Tasks.all
  @wordlists = Wordlists.all

  haml :task_list
end

get '/tasks/delete/:id' do
  params[:id] = clean(params[:id])

  @task = Tasks.first(id: params[:id])
  if @task
    @task.destroy
  else
    return 'No such task exists.'
  end

  redirect to('/tasks/list')
end

get '/tasks/edit/:id' do
  params[:id] = clean(params[:id])
  @task = Tasks.first(id: params[:id])
  @wordlists = Wordlists.all

  @rules = []
  # list wordlists that can be used
  Dir.foreach('control/rules/') do |item|
    next if item == '.' || item == '..'
      @rules << item
  end

  haml :task_edit
end

post '/tasks/edit/:id' do
  return 'You must provide a name for your task.' if !params[:name] || params[:name].nil?

  params[:wordlist] = clean(params[:wordlist]) if params[:wordlist] && !params[:wordlist].nil?
  params[:attackmode] = clean(params[:attackmode]) if params[:attackmode] && !params[:attackmode].nil?
  params[:rule] = clean(params[:rule]) if params[:rule] && !params[:rule] && !params[:rule].nil?
  params[:name] = clean(params[:name])

  settings = Settings.first
  wordlist = Wordlists.first(id: params[:wordlist])

  if settings && !settings.hcbinpath
    return 'No hashcat binary path is defined in global settings.'
  end

  task = Tasks.first(id: params[:id])
  task.name = params[:name]

  task.hc_attackmode = params[:attackmode]

  if params[:attackmode] == 'dictionary'
    task.wl_id = wordlist.id
    task.hc_rule = params[:rule]
    task.hc_mask = 'NULL'
  elsif params[:attackmode] == 'maskmode'
    task.wl_id = 'NULL'
    task.hc_rule = 'NULL'
    task.hc_mask = params[:mask]
  end
  task.save

  redirect to('/tasks/list')
end

get '/tasks/create' do
  settings = Settings.first

  # TODO present better error msg
  if settings.nil?
    return 'You must define hashcat\'s binary path in global settings first.'
  end

  tasks = Tasks.all
  warning('You need to have tasks before starting a job') if tasks.empty?

  @rules = []
  # list wordlists that can be used
  Dir.foreach('control/rules/') do |item|
    next if item == '.' || item == '..'
      @rules << item
  end

  @wordlists = Wordlists.all

  haml :task_edit
end

post '/tasks/create' do
  return 'You must provide a name for your task.' if !params[:name] || params[:name].nil?

  params[:wordlist] = clean(params[:wordlist]) if params[:wordlist] && !params[:wordlist].nil?
  params[:attackmode] = clean(params[:attackmode]) if params[:attackmode] && !params[:attackmode].nil?
  params[:rule] = clean(params[:rule]) if params[:rule] && !params[:rule] && !params[:rule].nil?
  params[:name] = clean(params[:name])

  settings = Settings.first
  wordlist = Wordlists.first(id: params[:wordlist])

  if settings && !settings.hcbinpath
    return 'No hashcat binary path is defined in global settings.'
  end

  task = Tasks.new
  task.name = params[:name]

  task.hc_attackmode = params[:attackmode]

  if params[:attackmode] == 'dictionary'
    task.wl_id = wordlist.id
    task.hc_rule = params[:rule]
  elsif params[:attackmode] == 'maskmode'
    task.hc_mask = params[:mask]
  end
  task.save

  redirect to('/tasks/list')
end

############################

##### job controllers #####

get '/jobs/list' do
  @targets_cracked = {}
  @customer_names = {}

  @jobs = Jobs.all(order: [:id.desc])
  @tasks = Tasks.all
  @jobtasks = Jobtasks.all

  @jobs.each do |entry|
    @targets_cracked[entry.id] = Targets.count(jobid: [entry.id], cracked: 1)
  end

  @jobs.each do |entry|
    @customers = Customers.first(id: [entry.customer_id])
    @customer_names[entry.customer_id] = @customers.name
  end

  haml :job_list
end

get '/jobs/delete/:id' do
  params[:id] = clean(params[:id])

  @job = Jobs.first(id: params[:id])
  if !@job
    return 'No such job exists.'
  else
    @jobtasks = Jobtasks.all(job_id: params[:id])
    @jobtasks.each do |jobtask|
      jobtask.destroy unless jobtask.nil?
    end
    @job.destroy
  end

  redirect to('/jobs/list')
end

get '/jobs/create' do
  @customers = Customers.all
  redirect to('/customers/create') if @customers.empty?

  @tasks = Tasks.all
  redirect to('/tasks/create') if @tasks.empty?

  # we do this so we can embedded ruby into js easily
  # js handles adding/selecting tasks associated with new job
  taskhashforjs = {}
  @tasks.each do |task|
    taskhashforjs[task.id] = task.name
  end
  @taskhashforjs = taskhashforjs.to_json

  haml :job_edit
end

post '/jobs/create' do
  return 'You must provide a name for your job.' if !params[:name] || params[:name].nil?
  return 'You must provide a customer for your job.' if !params[:customer] || params[:customer].nil?
  return 'You must provide a task to your job' if !params[:tasks] || params[:tasks].nil?

  params[:name] = clean(params[:name])
  params[:customer] = clean(params[:customer])

  # create new job
  job = Jobs.new
  job.name = params[:name]
  job.last_updated_by = getUsername
  job.customer_id = params[:customer]
  job.save

  # assign tasks to the job
  assignTasksToJob(params[:tasks], job.id)

  redirect to("/jobs/#{job.id}/upload/hashfile")
end

get '/jobs/:id/upload/hashfile' do
  params[:id] = clean(params[:id])

  @job = Jobs.first(id: params[:id])
  return 'No such job exists' unless @job

  haml :upload_hashfile
end

post '/jobs/:id/upload/hashfile' do
  params[:id] = clean(params[:id])

  @job = Jobs.first(id: params[:id])
  return 'No such job exists' unless @job

  # temporarily save file for testing
  hash = rand(36**8).to_s(36)
  hashfile = "control/hashes/hashfile_upload_jobid-#{@job.id}-#{hash}.txt"

  # Parse uploaded file into an array
  hash_array = []
  whole_file_as_string_object = params[:file][:tempfile].read
  File.open(hashfile, 'w') { |f| f.write(whole_file_as_string_object) }
  whole_file_as_string_object.each_line do |line|
    hash_array << line
  end

  # save location of tmp hash file
  @job.targetfile = hashfile
  @job.save

  redirect to("/jobs/#{@job.id}/upload/verify_filetype/#{hash}")
end

get '/jobs/:id/upload/verify_filetype/:hash' do
  params[:id] = clean(params[:id])
  params[:hash] = clean(params[:hash])

  @filetypes = detectHashfileType("control/hashes/hashfile_upload_jobid-#{params[:id]}-#{params[:hash]}.txt")
  @job = Jobs.first(id: params[:id])
  haml :verify_filetypes
end

post '/jobs/:id/upload/verify_filetype' do
  params[:filetype] = clean(params[:filetype])
  params[:hash] = clean(params[:hash])

  filetype = params[:filetype]
  hash = params[:hash]

  redirect to("/jobs/#{params[:id]}/upload/verify_hashtype/#{hash}/#{filetype}")
end

get '/jobs/:id/upload/verify_hashtype/:hash/:filetype' do
  params[:id] = clean(params[:id])
  params[:hash] = clean(params[:hash])
  params[:filetype] = clean(params[:filetype])

  @hashtypes = detectHashType("control/hashes/hashfile_upload_jobid-#{params[:id]}-#{params[:hash]}.txt", params[:filetype])
  @job = Jobs.first(id: params[:id])
  haml :verify_hashtypes
end

post '/jobs/:id/upload/verify_hashtype' do
  return 'You must specify a valid hashfile type' if !params[:filetype] || params[:filetype].nil?

  params[:filetype] = clean(params[:filetype])
  params[:hash] = clean(params[:hash]) if params[:hash] && !params[:hash].nil?
  params[:hashtype] = clean(params[:hashtype]) if params[:hashtype] && !params[:hashtype].nil?
  params[:manualHash] = clean(params[:manualHash]) if params[:hashtype] && !params[:hashtype].nil?
  params[:id] = clean(params[:id])

  filetype = params[:filetype]
  hash = params[:hash]

  if params[:hashtype] == '99999'
    hashtype = params[:manualHash]
  else
    hashtype = params[:hashtype]
  end

  hash_file = "control/hashes/hashfile_upload_jobid-#{params[:id]}-#{params[:hash]}.txt"

  hash_array = []
  File.open(hash_file, 'r').each do |line|
    hash_array << line
  end

  @job = Jobs.first(id: params[:id])
  customer_id = @job.customer_id

  unless importHash(hash_array, customer_id, params[:id], filetype, hashtype)
    return 'Error importing hash' # need to better handle errors
  end

  # Delete file, no longer needed
  File.delete(hash_file)

  redirect to('/jobs/list')
end

get '/jobs/edit/:id' do
  params[:id] = clean(params[:id])

  @job = Jobs.first(id: params[:id])
  if !@job
    return 'No such job exists.'
  else
    @tasks = Tasks.all
    @jobtasks = Jobtasks.all(job_id: params[:id])
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

post '/jobs/edit/:id' do
  return 'You must specify task you want to edit' if !params[:tasks] || params[:tasks].nil?

  params[:id] = clean(params[:id])  if params[:id] && !params[:id].nil?
  params[:tasks] = clean_array(params[:tasks]) if params[:tasks] && !params[:tasks].nil?

  values = request.POST

  @job = Jobs.first(id: params[:id])
  if !@job
    return 'No such job exists.'
  else
    # update job
    # assign tasks to the job before
    p values
    if values['tasks'] != nil
      assignTasksToJob(params[:tasks], @job.id)
      values.delete('tasks')
    end
    @job.update(values)

  end

  redirect to('/jobs/list')
end

get '/jobs/start/:id' do
  params[:id] = clean(params[:id])

  tasks = []
  @job = Jobs.first(id: params[:id])
  if !@job
    return 'No such job exists.'
  else
    @jobtasks = Jobtasks.all(job_id: params[:id])
    if !@jobtasks
      return 'This job has no tasks to run.'
    else
      @jobtasks.each do |jt|
        tasks << Tasks.first(id: jt.task_id)
      end
    end
  end

  tasks.each do |task|
    jt = Jobtasks.first(task_id: task.id, job_id: @job.id)
    # do not start tasks if they have already been completed.
    # set all other tasks to status of queued
    unless jt.status == 'Completed'
      # set jobtask status to queued
      jt.status = 'Queued'
      jt.save
      # toggle the job status to run
      @job.status = 'Queued'
      @job.save
      cmd = buildCrackCmd(@job.id, task.id)
      cmd = cmd + ' | tee -a control/outfiles/hcoutput_' + @job.id.to_s + '.txt'
      p 'ENQUE CMD: ' + cmd
      Resque.enqueue(Jobq, jt.id, cmd)
    end
  end

  return 'All tasks for this job have been completed. To prevent overwriting your results, you will need to create a new job with the same tasks in order to rerun the job.' if @job.status == 'Completed'

  redirect to('/home')
end

get '/jobs/queue' do
  if isDevelopment?
    redirect to('http://192.168.15.244:5678')
  else
    return redis.keys
  end
end

get '/jobs/stop/:id' do
  params[:id] = clean(params[:id])

  tasks = []
  @job = Jobs.first(id: params[:id])
  if !@job
    return 'No such job exists.'
  else
    @jobtasks = Jobtasks.all(job_id: params[:id])
    if !@jobtasks
      return 'This job has no tasks to stop.'
    else
      @jobtasks.each do |jt|
        tasks << Tasks.first(id: jt.task_id)
      end
    end
  end

  @job.status = 'Paused'
  @job.save

  tasks.each do |task|
    jt = Jobtasks.first(task_id: task.id, job_id: @job.id)
    # do not stop tasks if they have already been completed.
    # set all other tasks to status of Canceled
    if not jt.status == 'Completed' and not jt.status == 'Running'
      jt.status = 'Canceled'
      jt.save
      cmd = buildCrackCmd(@job.id, task.id)
      cmd = cmd + ' | tee -a control/outfiles/hcoutput_' + @job.id.to_s + '.txt'
      puts 'STOP CMD: ' + cmd
      Resque::Job.destroy('hashcat', Jobq, jt.id, cmd)
    end
  end

  tasks.each do |task|
    jt = Jobtasks.first(task_id: task.id, job_id: @job.id)
    if jt.status == 'Running'
      redirect to("/jobs/stop/#{jt.job_id}/#{jt.task_id}")
    end
  end

  redirect to('/jobs/list')
end

get '/jobs/stop/:jobid/:taskid' do
  params[:jobid] = clean(params[:jobid])
  params[:taskid] = clean(params[:taskid])

  # validate if running
  jt = Jobtasks.first(job_id: params[:jobid], task_id: params[:taskid])
  unless jt.status == 'Running'
    return 'That specific Job and Task is not currently running.'
  end
  # find pid
  pid = `sudo ps -ef | grep hashcat | grep hc_cracked_#{params[:jobid]}_#{params[:taskid]}.txt | grep -v sudo | awk '{print $2}'`
  pid = pid.chomp

  # update jobtasks to "canceled"
  jt.status = 'Canceled'
  jt.save

  # Kill jobtask
  `sudo kill -9 #{pid}`

  referer = request.referer.split('/')

  if referer[3] == 'home'
    redirect to('/home')
  elsif referer[3] == 'jobs'
    redirect to('/jobs/list')
  end
end

############################

##### job task controllers #####

get '/jobs/:jobid/task/delete/:jobtaskid' do
  params[:jobid] = clean(params[:jobid])
  params[:jobtaskid] = clean(params[:jobtaskid])

  @job = Jobs.first(id: params[:jobid])
  if !@job
    return 'No such job exists.'
  else
    @jobtask = Jobtasks.first(id: params[:jobtaskid])
    @jobtask.destroy
  end

  redirect to("/jobs/edit/#{@job.id}")
end

############################

##### Global Settings ######

get '/settings' do
  @settings = Settings.first

  if @settings && @settings.maxtasktime.nil?
    warning('Max task time must be defined in seconds (864000 is 10 days)')
  end

  haml :global_settings
end

post '/settings' do
  values = request.POST

  @settings = Settings.first

  if @settings.nil?
    # create settings for the first time
    # set max task time if none is provided
    values['maxtasktime'] = '864000' if @settings && @settings.maxtasktime.nil?
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

get '/download' do
  params[:custid] = clean(params[:custid]) if params[:custid]
  params[:jobid] = clean(params[:jobid]) if params[:jobid]

  if params[:custid] && !params[:custid].empty?
    if params[:jobid] && !params[:jobid].empty?
      @cracked_results = Targets.all(fields: [:plaintext, :originalhash, :username], customerid: params[:custid], jobid: params[:jobid], cracked: '1')
    else
      @cracked_results = Targets.all(fields: [:plaintext, :originalhash, :username], customerid: params[:custid], cracked: 1)
    end
  else
    @cracked_results = Targets.all(fields: [:plaintext, :originalhash, :username], cracked: 1)
  end

  return 'No Results available.' if @cracked_results.nil?

  # Write temp output file
  if params[:custid] && !params[:custid].empty?
    if params[:jobid] && !params[:jobid].empty?
      file_name = "found_#{params[:custid]}_#{params[:jobid]}.txt"
    else
      file_name = "found_#{params[:custid]}.txt"
    end
  else
    file_name = 'found_all.txt'
  end

  file_name = 'control/outfiles/' + file_name

  File.open(file_name, 'w') do |f|
    @cracked_results.each do |entry|
      line = entry.username + ':' + entry.originalhash + ':' + entry.plaintext
      f.puts line
    end
  end

  send_file file_name, filename: file_name, type: 'Application/octet-stream'

end

############################

##### Word Lists ###########

get '/wordlists/list' do
  @wordlists = Wordlists.all

  haml :wordlist_list
end

get '/wordlists/add' do
  haml :wordlist_add
end

get '/wordlists/delete/:id' do
  params[:id] = clean(params[:id])

  @wordlist = Wordlists.first(id: params[:id])
  if not @wordlist
    return 'no such wordlist exists'
  else
    # check if wordlist is in use
    @task_list = Tasks.all(wl_id: @wordlist.id)
    if !@task_list.empty?
      return 'This word list is associated with a task, it cannot be deleted'
    end

    # remove from filesystem
    File.delete(@wordlist.path)

    # delete from db
    @wordlist.destroy
  end
  redirect to('/wordlists/list')
end

post '/wordlists/upload/' do
  return 'You must specify a name for your word list' if !params[:name] || params[:name].nil?

  params[:name] = clean(params[:name])

  # Replace white space with underscore.  We need more filtering here too
  upload_name = params[:name]
  upload_name = upload_name.downcase.tr(' ', '_')

  # Change to date/time ?
  rand_str = rand(36**36).to_s(36)

  # Save to file
  file_name = "control/wordlists/wordlist-#{upload_name}-#{rand_str}.txt"
  File.open(file_name, 'wb') { |f| f.write(params[:file][:tempfile].read) }

  # Identify how many lines/enteries there are
  size = File.foreach(file_name).inject(0) { |c, line| c + 1 }

  wordlist = Wordlists.new
  wordlist.name = upload_name # what XSS?
  wordlist.path = file_name
  wordlist.size = size
  wordlist.save

  redirect to('/wordlists/list')
end

############################

##### Purge Data ###########

get '/purge' do
  params[:jobid] = clean(params[:jobid])

  @job_cracked = {}
  @job_total = {}
  @job_id_name = {}
  @target_jobids = []
  @all_cracked = 0
  @all_total = 0
  @targets = Targets.all(fields: [:jobid], unique: true)
  @targets.each do |entry|
    @target_jobids.push(entry.jobid)
  end

  @jobs = Jobs.all
  @jobs.each do |entry|
    @job_id_name[entry.id] = entry.name
  end

  @target_jobids.each do |entry|
    @job_cracked[entry] = Targets.count(jobid: [entry], cracked: 1)
    @all_cracked = @all_cracked + @job_cracked[entry]
    @job_total[entry] = Targets.count(jobid: [entry])
    @all_total = @all_total + @job_total[entry]
  end

  haml :purge
end

get '/purge/:id' do
  params[:id] = clean(params[:id])

  if params[:id] == 'all'
    @targets = Targets.all
    @targets.destroy
  else
    @targets = Targets.all(jobid: params[:id])
    @targets.destroy
  end

  redirect to('/purge')
end

############################

##### Analysis #############

# displays analytics for a specific client, job
get '/analytics' do

  params[:custid] = clean(params[:custid]) if params[:custid]
  params[:jobid] = clean(params[:jobid]) if params[:jobid]

  @custid = params[:custid]
  @jobid = params[:jobid]
  @button_select_customers = Customers.all

  if params[:custid] && !params[:custid].empty?
    @button_select_jobs = Jobs.all(customer_id: params[:custid])
  end

  if params[:custid] && !params[:custid].empty?
    @customers = Customers.first(id: params[:custid])
  else
    @customers = Customers.all
  end

  if params[:custid] && !params[:custid].empty?
    if params[:jobid] && !params[:jobid].empty?
      @jobs = Jobs.first(id: params[:jobid])
    else
      @jobs = Jobs.all
    end
  end

  # get results of specific customer if custid is defined
  if params[:custid] && !params[:custid].empty?
    # if we have a job
    if params[:jobid] && !params[:jobid].empty?
      # Used for Total Hashes Cracked doughnut: Customer: Job
      @cracked_pw_count = Targets.count(customerid: params[:custid], jobid: params[:jobid], cracked: 1)
      @uncracked_pw_count = Targets.count(customerid: params[:custid], jobid: params[:jobid], cracked: 0)

      # Used for Total Accounts table: Customer: Job
      @total_accounts = Targets.count(customerid: params[:custid], jobid: params[:jobid])

      # Used for Total Unique Users and originalhashes Table: Customer: Job
      @total_users_originalhash = Targets.all(fields: [:username, :originalhash], customerid: params[:custid], jobid: params[:jobid])

      # Used for Total Run Time: Customer: Job
      @total_run_time = Jobtasks.sum(:run_time, conditions: {:job_id => params[:jobid]})
    else
      # Used for Total Hashes Cracked doughnut: Customer
      @cracked_pw_count = Targets.count(customerid: params[:custid], cracked: 1)
      @uncracked_pw_count = Targets.count(customerid: params[:custid], cracked: 0)

      # Used for Total Accounts Table: Customer
      @total_accounts = Targets.count(customerid: params[:custid])

      # Used for Total Unique Users and original hashes Table: Customer
      @total_users_originalhash = Targets.all(fields: [:username, :originalhash], customerid: params[:custid])

      # Used for Total Run Time: Customer:
      # I'm ashamed of the code below
      @jobs = Jobs.all(customer_id: params[:custid])
      @total_run_time = 0
      @jobs.each do |job|
        @query_results = Jobtasks.sum(:run_time, conditions: {:job_id => params[:jobid]})
        unless @query_results.nil?
          @total_run_time = @total_run_time + @query_results
        end
      end
    end
  else
    # Used for Total Hash Cracked Doughnut: Total
    @cracked_pw_count = Targets.count(cracked: 't')
    @uncracked_pw_count = Targets.count(cracked: 'f')

    # Used for Total Accounts Table: Total
    @total_accounts = Targets.count

    # Used for Total Unique Users and originalhashes Tables: Total
    @total_users_originalhash = Targets.all(fields: [:username, :originalhash])

    # Used for Total Run Time:
    @total_run_time = Jobtasks.sum(:run_time)
  end

  @passwords = @cracked_results.to_json

  # Unique Usernames
  @total_unique_users_count = Set.new

  # Unique Passwords
  @total_unique_originalhash_count = Set.new

  @total_users_originalhash.each do |entry|
    @total_unique_users_count.add(entry.username)
    @total_unique_originalhash_count.add(entry.originalhash)
  end

  # Total Crack Time

  haml :analytics
end

# callback for d3 graph displaying passwords by length
get '/analytics/graph1' do

  params[:custid] = clean(params[:custid]) if params[:custid]
  params[:jobid] = clean(params[:jobid]) if params[:jobid]

  @counts = []
  @passwords = {}

  if params[:custid] && !params[:custid].empty?
    if params[:jobid] && !params[:jobid].empty?
      @cracked_results = Targets.all(fields: [:plaintext], customerid: params[:custid], jobid: params[:jobid], cracked: true)
    else
      @cracked_results = Targets.all(fields: [:plaintext], customerid: params[:custid], cracked: true)
    end
  else
    @cracked_results = Targets.all(fields: [:plaintext], cracked: true)
  end

  @cracked_results.each do |crack|
    unless crack.plaintext.nil?
      unless crack.plaintext.length == 0
        # get password count by length
        len = crack.plaintext.length
        if @passwords[len].nil?
          @passwords[len] = 1
        else
          @passwords[len] = @passwords[len].to_i + 1
        end
      end
    end
  end

  # Sort on key
  @passwords = @passwords.sort.to_h

  # convert to array of json objects for d3
  @passwords.each do |key, value|
    @counts << {length: key, count: value}
  end

  return @counts.to_json
end

# callback for d3 graph displaying top 10 passwords
get '/analytics/graph2' do

  params[:custid] = clean(params[:custid]) if params[:custid]
  params[:jobid] = clean(params[:jobid]) if params[:jobid]

  plaintext = []
  if params[:custid] && !params[:custid].empty?
    if params[:jobid] && !params[:jobid].empty?
      @cracked_results = Targets.all(fields: [:plaintext], customerid: params[:custid], jobid: params[:jobid], cracked: true)
    else
      @cracked_results = Targets.all(fields: [:plaintext], customerid: params[:custid], cracked: true)
    end
  else
    @cracked_results = Targets.all(fields: [:plaintext], cracked: true)
  end
  @cracked_results.each do |crack|
    unless crack.plaintext.nil?
      plaintext << crack.plaintext unless crack.plaintext.length == 0
    end
  end

  @toppasswords = []
  @top10passwords = {}
  # get top 10 passwords
  plaintext.each do |pass|
    if @top10passwords[pass].nil?
      @top10passwords[pass] = 1
    else
      @top10passwords[pass] += 1
    end
  end

  # sort and convert to array of json objects for d3
  @top10passwords = @top10passwords.sort_by { |key, value| value }.reverse.to_h
  # we only need top 10
  @top10passwords = Hash[@top10passwords.sort_by { |k, v| -v }[0..9]]
  # convert to array of json objects for d3
  @top10passwords.each do |key, value|
    @toppasswords << { password: key, count: value }
  end

  return @toppasswords.to_json
end

# callback for d3 graph displaying top 10 base words
get '/analytics/graph3' do

  params[:custid] = clean(params[:custid]) if params[:custid]
  params[:jobid] = clean(params[:jobid]) if params[:jobid]

  plaintext = []
  if params[:custid] && !params[:custid].empty?
    if params[:jobid] && !params[:jobid].empty?
      @cracked_results = Targets.all(fields: [:plaintext], customerid: params[:custid], jobid: params[:jobid], cracked: true)
    else
      @cracked_results = Targets.all(fields: [:plaintext], customerid: params[:custid], cracked: true)
    end
  else
    @cracked_results = Targets.all(fields: [:plaintext], cracked: true)
  end
  @cracked_results.each do |crack|
    unless crack.plaintext.nil?
      plaintext << crack.plaintext unless crack.plaintext.length == 0
    end
  end

  @topbasewords = []
  @top10basewords = {}
  # get top 10 basewords
  plaintext.each do |pass|
    word_just_alpha = pass.gsub(/^[^a-z]*/i, '').gsub(/[^a-z]*$/i, '')
    if @top10basewords[word_just_alpha].nil?
      @top10basewords[word_just_alpha] = 1
    else
      @top10basewords[word_just_alpha] += 1
    end
  end

  # sort and convert to array of json objects for d3
  @top10basewords = @top10basewords.sort_by { |key, value| value }.reverse.to_h
  # we only need top 10
  @top10basewords = Hash[@top10basewords.sort_by { |k, v| -v }[0..9]]
  # convert to array of json objects for d3
  @top10basewords.each do |key, value|
    @topbasewords << { password: key, count: value }
  end

  return @topbasewords.to_json
end

############################

##### search ###############

get '/search' do
  haml :search
end

post '/search' do
  @customers = Customers.all

  if params[:value].nil? || !params[:value]
    warning('Please provide a search term')
    redirect to('/search')
  else
    value = clean(params[:value])
  end

  if params[:search_type] == 'hash'
    hash = clean(params[:value])
  elsif params[:search_type] == 'username'
    username = clean(params[:value])
  else
    return 'You need to provide a search type'
  end

  if username
    @results = Targets.all(username: username)
  elsif hash
    @results = Targets.all(originalhash: hash)
  end

  haml :search_post
end

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
def buildCrackCmd(jobid, taskid)
  # order of opterations -m hashtype -a attackmode is dictionary? set wordlist, set rules if exist file/hash
  settings = Settings.first
  hcbinpath = settings.hcbinpath
  maxtasktime = settings.maxtasktime
  @task = Tasks.first(id: taskid)
  @job = Jobs.first(id: jobid)
  @targets = Targets.first(jobid: jobid)
  hashtype = @targets.hashtype.to_s
  attackmode = @task.hc_attackmode.to_s
  mask = @task.hc_mask
  wordlist = Wordlists.first(id: @task.wl_id)

  target_file = 'control/hashes/hashfile_' + jobid.to_s + '_' + taskid.to_s + '.txt'

  # we assign and write output file before hashcat.
  # if hashcat creates its own output it does so with
  # elvated permissions and we wont be able to read it
  crack_file = 'control/outfiles/hc_cracked_' + @job.id.to_s + '_' + @task.id.to_s + '.txt'
  File.open(crack_file, 'w')

  if attackmode == 'bruteforce'
    cmd = 'sudo ' + hcbinpath + ' -m ' + hashtype + ' --potfile-disable' + ' --runtime=' + maxtasktime + ' --outfile-format 3 ' + ' --outfile ' + crack_file + ' ' + ' -a 3 ' + target_file
  elsif attackmode == 'maskmode'
    cmd = 'sudo ' + hcbinpath + ' -m ' + hashtype + ' --potfile-disable' + ' --runtime=' + maxtasktime + ' --outfile-format 3 ' + ' --outfile ' + crack_file + ' ' + ' -a 3 ' + target_file + ' ' + mask
  elsif attackmode == 'dictionary'
    if @task.hc_rule == 'none'
      cmd = 'sudo ' + hcbinpath + ' -m ' + hashtype + ' --potfile-disable' + ' --outfile-format 3 ' + ' --outfile ' + crack_file + ' ' + target_file + ' ' + wordlist.path
    else
      cmd = 'sudo ' + hcbinpath + ' -m ' + hashtype + ' --potfile-disable' + ' --outfile-format 3 ' + ' --outfile ' + crack_file + ' ' + ' -r ' + 'control/rules/' + @task.hc_rule + ' ' + target_file + ' ' + wordlist.path
    end
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

helpers do
  def warning(txt)
    if @warnings != nil
      @warnings << txt
    else
      @warnings = []
      @warnings << txt
    end
    @warnings
  end

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

  def clean(text)
    return text.gsub(/[<>'"()\/\\]*/i, '')
  end

  def clean_array(array)
    clean_array = []
    array.each do |entry|
      clean_array.push(clean(entry))
    end
    return clean_array
  end
end
