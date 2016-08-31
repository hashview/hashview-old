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
    sess = Sessions.first(session_key: session[:session_id])
    sess.destroy if sess
  end
  redirect to('/')
end

post '/login' do
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
  redirect to('/') unless validSession?
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
  redirect to('/') unless validSession?
  @results = `ps awwux | grep -i Hashcat | egrep -v "(grep|screen|SCREEN|resque|^$)" | grep -v sudo`
  @jobs = Jobs.all
  @jobtasks = Jobtasks.all
  @tasks = Tasks.all
  @recentlycracked = Targets.all(limit: 10, cracked: 1)
  @customers = Customers.all

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
    if j.status
      @alltargets = Targets.all(jobid: j.id)
      @crackedtargets = Targets.all(jobid: j.id, cracked: 1)
      @alltargets = @alltargets.count
      @crackedtargets = @crackedtargets.count
      @progress = (@crackedtargets.to_f / @alltargets.to_f) * 100
    else
      @alltargets = 0
      @crackedtargets = 0
      @progress = 0
    end
  end

  haml :home
end

get '/register' do
  haml :register
end

############################

### customer controllers ###

get '/customer/list' do
  redirect to('/') unless validSession?

  @customers = Customers.all
  @total_jobs = []
  @total_hashes = []

  @customers.each do | customer |
    @total_jobs[customer.id] = Jobs.count(customer_id: customer.id)
    @total_hashes[customer.id] = Targets.count(customerid: customer.id)
  end

  haml :customer_list
end

get '/customer/create' do
  redirect to('/') unless validSession?

  haml :customer_edit
end

post '/customer/create' do
  customer = Customers.new
  customer.name = params[:name]
  customer.description = params[:desc]
  customer.save

  redirect to('customer/list')
end

get '/customer/edit/:id' do
  redirect to('/') unless validSession?

  @customer = Customers.first(id: params[:id])

  haml :customer_edit
end

post '/customer/edit/:id' do
  redirect to('/') unless validSession?

  customer = Customers.first(id: params[:id])
  customer.name = params[:name]
  customer.description = params[:desc]
  customer.save

  redirect to('customer/list')
end

get '/customer/delete/:id' do
  redirect to('/') unless validSession?

  @customer = Customers.first(id: params[:id])
  @customer.destroy unless @customer.nil?

  @jobs = Jobs.all(customer_id: params[:id])
  @jobs.destroy unless @jobs.nil?

  @targets = Targets.all(customerid: params[:id])
  @targets.destroy unless @targets.nil?

  redirect to('/customer/list')
end

############################

##### task controllers #####

get '/task/list' do
  redirect to('/') unless validSession?

  @tasks = Tasks.all
  @wordlists = Wordlists.all

  haml :task_list
end

get '/task/delete/:id' do
  redirect to('/') unless validSession?

  @task = Tasks.first(id: params[:id])
  if @task
    @task.destroy
  else
    return 'No such task exists.'
  end

  redirect to('/task/list')
end

get '/task/edit/:id' do
  redirect to('/') unless validSession?

  return 'Page under contruction.'
end

get '/task/create' do
  redirect to('/') unless validSession?

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

  haml :task_create
end

post '/task/create' do
  redirect to('/') unless validSession?

  settings = Settings.first
  wordlist = Wordlists.first(id: params[:wordlist])
  puts wordlist.path

  if settings && !settings.hcbinpath
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
  redirect to('/') unless validSession?

  @targets_cracked = {}
  @customer_names = {}

  @jobs = Jobs.all
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

get '/job/delete/:id' do
  redirect to('/') unless validSession?

  @job = Jobs.first(id: params[:id])
  if !@job
    return 'No such job exists.'
  else
    @job.destroy
  end

  redirect to('/job/list')
end

get '/job/create' do
  redirect to('/') unless validSession?

  @customers = Customers.all
  redirect to('/customer/create') if @customers.empty?

  @tasks = Tasks.all
  redirect to('/task/create') if @tasks.empty?

  # we do this so we can embedded ruby into js easily
  # js handles adding/selecting tasks associated with new job
  taskhashforjs = {}
  @tasks.each do |task|
    taskhashforjs[task.id] = task.name
  end
  @taskhashforjs = taskhashforjs.to_json

  haml :job_edit
end

post '/job/create' do
  redirect to('/') unless validSession?

  return 'You must assign a task to your job' unless params[:tasks]

  # create new job
  job = Jobs.new
  job.name = params[:name]
  job.last_updated_by = getUsername
  job.customer_id = params[:customer]
  job.save

  # assign tasks to the job
  assignTasksToJob(params[:tasks], job.id)

  redirect to("/job/#{job.id}/upload/hashfile")
end

get '/job/:id/upload/hashfile' do
  redirect to('/') unless validSession?

  @job = Jobs.first(id: params[:id])
  return 'No such job exists' unless @job

  haml :upload_hashfile
end

post '/job/:id/upload/hashfile' do
  redirect to('/') unless validSession?

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

  redirect to("/job/#{@job.id}/upload/verify_filetype/#{hash}")
end

get '/job/:id/upload/verify_filetype/:hash' do
  redirect to('/') unless validSession?

  @filetypes = detectHashfileType("control/hashes/hashfile_upload_jobid-#{params[:id]}-#{params[:hash]}.txt")
  @job = Jobs.first(id: params[:id])
  haml :verify_filetypes
end

post '/job/:id/upload/verify_filetype' do
  redirect to('/') unless validSession?

  filetype = params[:filetype]
  hash = params[:hash]

  redirect to("/job/#{params[:id]}/upload/verify_hashtype/#{hash}/#{filetype}")
end

get '/job/:id/upload/verify_hashtype/:hash/:filetype' do
  redirect to('/') unless validSession?

  @hashtypes = detectHashType("control/hashes/hashfile_upload_jobid-#{params[:id]}-#{params[:hash]}.txt", params[:filetype])
  @job = Jobs.first(id: params[:id])
  haml :verify_hashtypes
end

post '/job/:id/upload/verify_hashtype' do
  redirect to('/') unless validSession?

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
    return 'Error importing hash'  # need to better handle errors
  end

  # Delete file, no longer needed
  File.delete(hash_file)

  redirect to('/job/list')
end

get '/job/edit/:id' do
  redirect to('/') unless validSession?

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

post '/job/edit/:id' do
  redirect to('/') unless validSession?

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

  redirect to('/job/list')
end

get '/job/start/:id' do
  redirect to('/') unless validSession?

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
      @job.status = 1
      @job.save
      cmd = buildCrackCmd(@job.id, task.id)
      cmd = cmd + ' | tee -a control/outfiles/hcoutput_' + @job.id.to_s + '.txt'
      p 'ENQUE CMD: ' + cmd
      Resque.enqueue(Jobq, jt.id, cmd)
    end
  end

  unless @job.status
    return 'All tasks for this job have been completed. To prevent overwriting your results, you will need to create a new job with the same tasks in order to rerun the job.'
  end

  redirect to('/home')
end

get '/job/queue' do
  redirect to('/') unless validSession?
  if isDevelopment?
    redirect to('http://192.168.15.244:5678')
  else
    return redis.keys
  end
end

get '/job/stop/:id' do
  redirect to('/') unless validSession?

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

  @job.status = 0
  @job.save

  tasks.each do |task|
    jt = Jobtasks.first(task_id: task.id, job_id: @job.id)
    # do not stop tasks if they have already been completed.
    # set all other tasks to status of Canceled
    if not jt.status == 'Completed' and not jt.status == 'Running'
      jt.status = 'Canceled'
      jt.save
      #cmd = task.command + ' | tee -a control/outfiles/hcoutput_' + @job.id.to_s + '.txt'
      cmd = buildCrackCmd(@job.id, task.id)
      cmd = cmd + ' | tee -a control/outfiles/hcoutput_' + @job.id.to_s + '.txt'
      puts 'STOP CMD: ' + cmd
      Resque::Job.destroy('hashcat', Jobq, jt.id, cmd)
    end
  end

  tasks.each do |task|
    jt = Jobtasks.first(task_id: task.id, job_id: @job.id)
    if jt.status == 'Running'
      redirect to("/job/stop/#{jt.job_id}/#{jt.task_id}")
    end
  end

  redirect to('/job/list')
end

get '/job/stop/:jobid/:taskid' do
  redirect to('/') unless validSession?

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
  elsif referer[3] == 'job'
    redirect to('/job/list')
  end
end

############################

##### job controllers #####

get '/job/:jobid/task/delete/:jobtaskid' do
  redirect to('/') unless validSession?

  @job = Jobs.first(id: params[:jobid])
  if !@job
    return 'No such job exists.'
  else
    @jobtask = Jobtasks.first(id: params[:jobtaskid])
    @jobtask.destroy
  end

  redirect to("/job/edit/#{@job.id}")
end

############################

##### Global Settings ######

get '/settings' do
  redirect to('/') unless validSession?

  @settings = Settings.first

  if @settings && @settings.maxtasktime.nil?
    warning('Max task time must be defined in seconds (864000 is 10 days)')
  end

  haml :global_settings
end

post '/settings' do
  redirect to('/') unless validSession?

  values = request.POST

  @settings = Settings.first

  if @settings == nil
    # create settings for the first time
    # set max task time if none is provided
    if @settings && @setttings.maxtasktime.nil?
      values['maxtasktime'] = '864000'
    end
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
  redirect to('/') unless validSession?

  if params[:custid] && !params[:custid].empty?
    if params[:jobid] && !params[:jobid].empty?
      @cracked_results = Targets.all(fields: [:plaintext, :originalhash, :username], customerid: params[:custid], jobid: params[:jobid], cracked: '1')
    else
      @cracked_results = Targets.all(fields: [:plaintext, :originalhash, :username], customerid: params[:custid], cracked: 1)
    end
  else
    @cracked_results = Targets.all(fields: [:plaintext, :originalhash, :username], cracked: 1)
  end
  
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

get '/wordlist/list' do
  redirect to('/') unless validSession?

  @wordlists = Wordlists.all

  haml :wordlist_list
end

get '/wordlist/add' do
  redirect to('/') unless validSession?
  haml :wordlist_add
end

get '/wordlist/delete/:id' do
  redirect to('/') unless validSession?

  @wordlist = Wordlists.first(id: params[:id])
  if not @wordlist
    return 'no such wordlist exists'
  else
    # check if wordlist is in use
    tasks = Tasks.all(wl_id: @wordlist.id)
    if tasks
      return 'This word list is associated with a task, it cannot be deleted'
    end

    # remove from filesystem
    File.delete(@wordlist.path)

    # delete from db
    @wordlist.destroy
  end
  redirect to('/wordlist/list')
end

post '/wordlist/upload/' do
  redirect to('/') unless validSession?

  # require param name && file
  return 'File Name Required.' if params[:name].size == 0

  # Replace white space with underscore.  We need more filtering here too
  upload_name = params[:name]
  upload_name = upload_name.downcase.tr(' ', '_')

  # Change to date/time ?
  rand_str = rand(36**36).to_s(36)

  # Save to file
  file_name = "control/wordlists/wordlist-#{upload_name}-#{rand_str}.txt"
  File.open(file_name, 'wb') { |f| f.write(params[:file][:tempfile].read) }

  # Identify how many lines/enteries there are
  size = File.foreach(file_name).inject(0){ |c, line| c+1 }

  wordlist = Wordlists.new
  wordlist.name = upload_name # what XSS?
  wordlist.path = file_name
  wordlist.size = size
  wordlist.save

  redirect to('/wordlist/list')
end

############################

##### Purge Data ###########

get '/purge' do
  redirect to('/') unless validSession?

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
  redirect to('/') unless validSession?

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
      @total_run_time = Jobtasks.sum(:run_time, :conditions => ["job_id = #{params[:jobid]}"])
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
        @query_results = Jobtasks.sum(:run_time, :conditions => ["job_id = #{job.id}"])
        @total_run_time = @total_run_time + @query_results
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

  p @topbasewords.to_s

  return @topbasewords.to_json
end


############################

##### search ###############

get '/search' do
  redirect to('/') unless validSession?
  haml :search
end

post '/search' do
  redirect to('/') unless validSession?

  @plaintexts = Targets.all(originalhash: params[:hash])
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
  wordlist = Wordlists.first(id: @task.wl_id)

  target_file = 'control/hashes/hashfile_' + jobid.to_s + '_' + taskid.to_s + '.txt'

  # we assign and write output file before hashcat.
  # if hashcat creates its own output it does so with
  # elvated permissions and we wont be able to read it
  crack_file = 'control/outfiles/hc_cracked_' + @job.id.to_s + '_' + @task.id.to_s + '.txt'
  File.open(crack_file, 'w')

  if attackmode == '3'
    cmd = 'sudo ' + hcbinpath + ' -m ' + hashtype + ' --potfile-disable' + ' --runtime=' + maxtasktime + ' --outfile-format 3 ' + ' --outfile ' + crack_file + ' ' + ' -a ' + attackmode + ' ' + target_file
  elsif attackmode == '0'
    if @task.hc_rule == 'none'
      cmd = 'sudo ' + hcbinpath + ' -m ' + hashtype + ' --potfile-disable' + ' --outfile-format 3 ' + ' --outfile ' + crack_file + ' ' + target_file + ' ' + wordlist.path
    else
      cmd = 'sudo ' + hcbinpath + ' -m ' + hashtype + ' --potfile-disable' + ' --outfile-format 3 ' + ' --outfile ' + crack_file + ' ' +  ' -r ' + 'control/rules/' + @task.hc_rule + ' ' + target_file + ' ' + wordlist.path
    end
  end
  p cmd
  cmd
end

# Check if kraken has a job running
def isKrakenBusy?
  @results = `ps awwux | grep -i Hashcat | egrep -v "(grep|^$)" | grep -v sudo`
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
end
