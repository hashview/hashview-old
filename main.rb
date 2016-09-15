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

redis = Redis.new

# to start the resque web queue run the following from the command prompt:
# resque-web

# to start the rake task do: TERM_CHILD=1 QUEUE=* rake resque:work
# ^^^ should probably make an upstart for that

# validate every session
before /^(?!\/(login|register|logout))/ do
  if ! validSession?
    redirect to('/login')
  else
    settings = Settings.first
    if settings && settings.hcbinpath.nil?
      flash[:warning] = 'Annoying alert! You need to define hashcat\'s binary path in settings before I can work.'
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
        @del_session = Sessions.first(username: "#{usern}")
        @del_session.destroy if @del_session
      end
      # Create new session
      @curr_session = Sessions.create(username: "#{usern}", session_key: "#{session[:session_id]}")
      @curr_session.save

      redirect to('/home')
    end
  else
    flash[:error] = 'Invalid credentials.'
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
      @alltargets = Targets.count(hashfile_id: j.hashfile_id)
      @crackedtargets = Targets.count(hashfile_id: j.hashfile_id, cracked: 1)
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
  @total_hashfiles = []

  @customers.each do | customer |
    @total_jobs[customer.id] = Jobs.count(customer_id: customer.id)
    @total_hashes[customer.id] = Targets.count(customer_id: customer.id)
    @total_hashfiles[customer.id] = Hashfiles.count(customer_id: customer.id)
  end

  haml :customer_list
end

get '/customers/create' do
  haml :customer_edit
end

post '/customers/create' do
  varWash(params)

  if !params[:name] || params[:name].nil?
    flash[:error] = 'Customer must have a name.'
    redirect to('/customers/create')
  end

  customer = Customers.new
  customer.name = params[:name]
  customer.description = params[:desc]
  customer.save

  redirect to('customers/list')
end

get '/customers/edit/:id' do
  varWash(params)
  @customer = Customers.first(id: params[:id])

  haml :customer_edit
end

post '/customers/edit/:id' do
  varWash(params)
  if !params[:name] || params[:name].nil?
    flash[:error] = 'Customer must have a name.'
    redirect to('/customers/create')
  end

  customer = Customers.first(id: params[:id])
  customer.name = params[:name]
  customer.description = params[:desc]
  customer.save

  redirect to('customers/list')
end

get '/customers/delete/:id' do
  varWash(params)

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

  @hashfiles = Hashfiles.all(customer_id: params[:id])
  @hashfiles.destroy unless @hashfiles.nil?

  redirect to('/customers/list')
end

post '/customers/upload/hashfile' do
  varWash(params)

  if params[:hf_name].nil? || params[:hf_name].empty?
    flash[:error] = 'You must specificy a name for this hash file.'
    redirect to("/jobs/assign_hashfile?custid=#{params[:custid]}&jobid=#{params[:jobid]}")
  end

  if params[:file].nil? || params[:file].empty?
    flash[:error] = 'You must specify a hashfile.'
    redirect to("/jobs/assign_hashfile?custid=#{params[:custid]}&jobid=#{params[:jobid]}")
  end

  @job = Jobs.first(id: params[:jobid])
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
  hashfile = Hashfiles.new
  hashfile.name = params[:hf_name]
  hashfile.customer_id = params[:custid]
  hashfile.hash_str = hash
  hashfile.save

  @job.save

  redirect to("/customers/upload/verify_filetype?custid=#{params[:custid]}&jobid=#{params[:jobid]}&hashid=#{hashfile.id}")
end

get '/customers/upload/verify_filetype' do
  varWash(params)

  hashfile = Hashfiles.first(id: params[:hashid])

  @filetypes = detectHashfileType("control/hashes/hashfile_upload_jobid-#{params[:jobid]}-#{hashfile.hash_str}.txt")
  @job = Jobs.first(id: params[:jobid])
  haml :verify_filetypes
end

post '/customers/upload/verify_filetype' do
  varWash(params)

  redirect to("/customers/upload/verify_hashtype?custid=#{params[:custid]}&jobid=#{params[:jobid]}&hashid=#{params[:hashid]}&filetype=#{params[:filetype]}")
end

get '/customers/upload/verify_hashtype' do
  varWash(params)

  hashfile = Hashfiles.first(id: params[:hashid])

  @hashtypes = detectHashType("control/hashes/hashfile_upload_jobid-#{params[:jobid]}-#{hashfile.hash_str}.txt", params[:filetype])
  @job = Jobs.first(id: params[:jobid])
  haml :verify_hashtypes
end

post '/customers/upload/verify_hashtype' do
  varWash(params)

  if !params[:filetype] || params[:filetype].nil?
    flash[:error] = 'You must specify a valid hashfile type.'
    redirect to("/customers/upload/verify_hashtype?custid=#{params[:custid]}&jobid=#{params[:jobid]}&hashid=#{params[:hashid]}&filetype=#{params[:filetype]}")
  end

  filetype = params[:filetype]

  hashfile = Hashfiles.first(id: params[:hashid])

  if params[:hashtype] == '99999'
    hashtype = params[:manualHash]
  else
    hashtype = params[:hashtype]
  end

  hash_file = "control/hashes/hashfile_upload_jobid-#{params[:jobid]}-#{hashfile.hash_str}.txt"

  hash_array = []
  File.open(hash_file, 'r').each do |line|
    hash_array << line
  end

  @job = Jobs.first(id: params[:jobid])
  customer_id = @job.customer_id
  @job.hashfile_id = hashfile.id
  @job.save

  unless importHash(hash_array, customer_id, hashfile.id, filetype, hashtype)
    flash[:error] = 'Error importing hashes'
    redirect to("/customers/upload/verify_hashtype?custid=#{params[:custid]}&jobid=#{params[:jobid]}&hashid=#{params[:hashid]}&filetype=#{params[:filetype]}")
  end

  # detect if hash was previously cracked
  # build hash of hashes and plains
  cracks = {}
  @all_cracked_targets = Targets.all(cracked: 1)
  @all_cracked_targets.each do |ct|
    cracks[ct.originalhash.chomp.to_s] = ct.plaintext
  end

  # match already cracked hashes against hashes to be uploaded, update db
  # matches = []
  count = 0
  hash_array.each do |hash|
    hash = hash.chomp.to_s
    if cracks.key?(hash)
      Targets.all(originalhash: hash, cracked: 0).update(cracked: 1, plaintext: cracks[hash])
      count = count + 1
    end
  end

  if count > 0
    flash[:success] = "Hashview has previous cracked #{count} of these hashes"
  end

  # Delete file, no longer needed
  File.delete(hash_file)

  if params[:edit]
    redirect to("/jobs/assign_tasks?jobid=#{params[:jobid]}&edit=1")
  else
    redirect to("/jobs/assign_tasks?jobid=#{params[:jobid]}")
  end
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
  varWash(params)

  if params[:username].nil? || params[:username].empty?
    flash[:error] = 'You must have username.'
    redirect to('/accounts/create')
  end

  if params[:password].nil? || params[:password].empty?
    flash[:error] = 'You must have a password.'
    redirect to('/accounts/create')
  end

  if params[:confirm].nil? || params[:confirm].empty?
    flash[:error] = 'You must have a password.'
    redirect to('/accounts/create')
  end

  # validate that no other user account exists
  @users = User.all(username: params[:username])
  if @users.empty?
    if params[:password] != params[:confirm]
      flash[:error] = 'Passwords do not match'
      redirect to('/accounts/create')
    else
      new_user = User.new
      new_user.username = params[:username]
      new_user.password = params[:password]
      new_user.email = params[:email] unless params[:email].nil? || params[:email].empty?
      new_user.admin = 't'
      new_user.save
    end
  else
    flash[:error] = 'User account already exists.'
    redirect to('/accounts/create')
  end
  redirect to('/accounts/list')
end

get '/accounts/edit/:account_id' do
  varWash(params)

  @user = User.first(id: params[:account_id])

  haml :account_edit
end

post '/accounts/save' do
  varWash(params)

  if params[:account_id].nil? || params[:account_id].empty?
    flash[:error] = 'Invalid account.'
    redirect to('/accounts/list')
  end

  if params[:username].nil? || params[:username].empty?
    flash[:error] = 'Invalid username.'
    redirect to("/accounts/edit/#{params[:account_id]}")
  end

  if params[:password] != params[:confirm]
    flash[:error] = 'Passwords do not match'
    redirect to("/accounts/edit/#{params[:account_id]}")
  end

  user = User.first(id: params[:account_id])
  user.username = params[:username]
  user.password = params[:password] unless params[:password].nil? || params[:password].empty?
  user.email = params[:email] unless params[:email].nil? || params[:email].empty?
  user.save

  flash[:success] = 'Account successfuly updated.'

  redirect to('/accounts/list')
end

get '/accounts/delete/:id' do
  varWash(params)

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
  varWash(params)

  @task = Tasks.first(id: params[:id])
  if @task
    @task.destroy
  else
    return 'No such task exists.'
  end

  redirect to('/tasks/list')
end

get '/tasks/edit/:id' do
  varWash(params)
  @task = Tasks.first(id: params[:id])
  @wordlists = Wordlists.all
  @settings = Settings.first

  @rules = []
  # list wordlists that can be used
  Dir.foreach('control/rules/') do |item|
    next if item == '.' || item == '..'
      @rules << item
  end

  haml :task_edit
end

post '/tasks/edit/:id' do
  varWash(params)
  if !params[:name] || params[:name].nil?
    flash[:error] = 'The task requires a name.'
    redirect to("/tasks/edit/#{params[:id]}")
  end

  settings = Settings.first
  wordlist = Wordlists.first(id: params[:wordlist])

  if settings && !settings.hcbinpath
    flash[:error] = 'No hashcat binary path is defined in global settings.'
    redirect to('/settings')
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
  varWash(params)
  @settings = Settings.first

  # TODO present better error msg
  flash[:warning] = 'You must define hashcat\'s binary path in global settings first.' if @settings && @settings.hcbinpath.nil?

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
  varWash(params)
  settings = Settings.first
  if settings && !settings.hcbinpath
    flash[:error] = 'No hashcat binary path is defined in global settings.'
    redirect to('/settings')
  end

  if !params[:name] || params[:name].empty?
    flash[:error] = 'You must provide a name for your task!'
    redirect to('/tasks/create')
  end

  wordlist = Wordlists.first(id: params[:wordlist])

  # mask field cannot be empty
  if params[:attackmode] == 'maskmode'
    if !params[:mask] || params[:mask].empty?
      flash[:error] = 'Mask field cannot be left empty'
      redirect to('/tasks/create')
    end
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

  flash[:success] = "Task #{task.name} successfully created"

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
    @customers = Customers.first(id: [entry.customer_id])
    @customer_names[entry.customer_id] = @customers.name
  end

  haml :job_list
end

get '/jobs/delete/:id' do
  varWash(params)

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
  varWash(params)

  @customers = Customers.all
  @job = Jobs.first(id: params[:jobid])

  haml :job_edit
end

post '/jobs/create' do
  varWash(params)

  if !params[:job_name] || params[:job_name].empty?
    flash[:error] = 'You must provide a name for your job.'
    if params[:edit] == '1'
      redirect to("/jobs/create?custid=#{:custid}&jobid=#{:jobid}&edit=1")
    else
      redirect to('/jobs/create')
    end
  end

  if !params[:customer] || params[:customer].empty?
    if !params[:cust_name] || params[:cust_name].empty?
      flash[:error] = 'You must provide a customer for your job.'
      if params[:edit] == '1'
        redirect to("/jobs/create?custid=#{params[:custid]}&jobid=#{params[:jobid]}&edit=1")
      else
        redirect to('/jobs/create')
      end
    end
  end

  if params[:customer] && params[:customer] == 'add_new'
    if !params[:cust_name] || params[:cust_name].empty?
      flash[:error] = 'You must provide a customer name.'
      if params[:edit] == '1'
        redirect to("/jobs/create?custid=#{params[:custid]}&jobid=#{params[:jobid]}&edit=1")
      else
        redirect to('/jobs/create')
      end
    end
  end

  # Create a new customer if selected
  if params[:customer] == 'add_new' || params[:customer].nil?
    customer = Customers.new
    customer.name = params[:cust_name]
    customer.description = params[:cust_desc]
    customer.save
  end

  if params[:customer] == 'add_new' || params[:customer].nil?
    cust_id = customer.id
  else
    cust_id = params[:customer]
  end

  # create new or update existing job
  if params[:edit] == '1'
    job = Jobs.first(id: params[:jobid])
  else
    job = Jobs.new
  end
  job.name = params[:job_name]
  job.last_updated_by = getUsername
  job.customer_id = cust_id

  if params[:notify] == 'on'
    job.notify_completed = '1'
  else
    job.notify_completed = '0'
  end
  job.save

  if params[:edit] == '1'
    redirect to("/jobs/assign_hashfile?custid=#{cust_id}&jobid=#{job.id}&edit=1")
  else
    redirect to("/jobs/assign_hashfile?custid=#{cust_id}&jobid=#{job.id}")
  end
end

get '/jobs/assign_hashfile' do
  varWash(params)

  @hashfiles = Hashfiles.all(customer_id: params[:custid])
  @customer = Customers.first(id: params[:custid])
  @job = Jobs.first(id: params[:jobid])
  return 'No such job exists' unless @job

  haml :assign_hashfile
end

post '/jobs/assign_hashfile' do
  varWash(params)

  if params[:hash_file] != 'add_new'
    job = Jobs.first(id: params[:jobid])
    job.hashfile_id = params[:hash_file]
    job.save
  end

  if params[:edit] == '1'
    job = Jobs.first(id: params[:jobid])
    job.hashfile_id = params[:hash_file]
    job.save
  end

  if params[:edit]
    redirect to("/jobs/assign_tasks?jobid=#{params[:jobid]}&custid=#{params[:custid]}&hashid=#{params[:hash_file]}&edit=1")
  else
    redirect to("/jobs/assign_tasks?jobid=#{params[:jobid]}&custid=#{params[:custid]}&hashid=#{params[:hash_file]}")
  end
end

get '/jobs/assign_tasks' do
  varWash(params)

  @job = Jobs.first(id: params[:jobid])
  @jobtasks = Jobtasks.all(job_id: params[:jobid])
  @tasks = Tasks.all
  # we do this so we can embedded ruby into js easily
  # js handles adding/selecting tasks associated with new job
  taskhashforjs = {}
  @tasks.each do |task|
    taskhashforjs[task.id] = task.name
  end
  @taskhashforjs = taskhashforjs.to_json

  haml :assign_tasks
end

post '/jobs/assign_tasks' do
  varWash(params)

  if !params[:tasks] || params[:tasks].nil?
    if !params[:edit] || params[:edit].nil?
      flash[:error] = 'You must assign atleast one task'
      redirect to("/jobs/assign_tasks?jobid=#{params[:jobid]}&custid=#{params[:custid]}&hashid=#{params[:hash_file]}")
    end
  end

  job = Jobs.first(id: params[:jobid])
  job.status = 'Stopped'
  job.save

  # assign tasks to the job
  if params[:tasks] && !params[:tasks].nil?
    assignTasksToJob(params[:tasks], job.id)
  end

  flash[:success] = 'Successfully created job.'
  redirect to('/jobs/list')
end

get '/jobs/start/:id' do
  varWash(params)

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

  if @job.status == 'Completed'
    flash[:error] = 'All tasks for this job have been completed. To prevent overwriting your results, you will need to create a new job with the same tasks in order to rerun the job.'
    redirect to('/jobs/list')
  end

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
  varWash(params)

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
  varWash(params)

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

get '/jobs/remove_task' do
  varWash(params)

  @job = Jobs.first(id: params[:jobid])
  if !@job
    return 'No such job exists.'
  else
    @jobtask = Jobtasks.first(id: params[:jobtaskid])
    @jobtask.destroy
  end

  redirect to("/jobs/assign_tasks?custid=#{params[:custid]}&jobid=#{params[:jobid]}&edit=1")
end

############################

##### Global Settings ######

get '/settings' do
  @settings = Settings.first

  if @settings && @settings.maxtasktime.nil?
    flash[:info] = 'Max task time must be defined in seconds (86400 is 1 day)'
  end

  haml :global_settings
end

post '/settings' do
  varWash(params)

  if params[:hcbinpath].nil? || params[:hcbinpath].empty?
    flash[:error] = 'You must set the path for your hashcat binary.'
    redirect('/settings')
  end

  if params[:maxtasktime].nil? || params[:maxtasktime].empty?
    flash[:error] = 'You must set a max task time.'
    redirect('/settings')
  end

  values = request.POST

  @settings = Settings.first

  if @settings.nil?
    # create settings for the first time
    # set max task time if none is provided
    @newsettings = Settings.create(values)
    @newsettings.save
  else
    # update settings
    @settings.update(values)
  end

  flash[:success] = 'Settings updated successfully.'

  redirect to('/home')
end

############################

##### Downloads ############

get '/download' do
  varWash(params)

  if params[:custid] && !params[:custid].empty?
#    if params[:jobid] && !params[:jobid].empty?
    if params[:hf_id] && !params[:hf_id].nil?
      @cracked_results = Targets.all(fields: [:plaintext, :originalhash, :username], customer_id: params[:custid], hashfile_id: params[:hf_id], cracked: '1')
    else
      @cracked_results = Targets.all(fields: [:plaintext, :originalhash, :username], customer_id: params[:custid], cracked: 1)
    end
  else
    @cracked_results = Targets.all(fields: [:plaintext, :originalhash, :username], cracked: 1)
  end

  return 'No Results available.' if @cracked_results.nil?

  # Write temp output file
  if params[:custid] && !params[:custid].empty?
#    if params[:jobid] && !params[:jobid].empty?
    if params[:hf_id] && !params[:hf_id].nil?
      file_name = "found_#{params[:custid]}_#{params[:wl_id]}.txt"
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
  varWash(params)

  @wordlist = Wordlists.first(id: params[:id])
  if not @wordlist
    return 'no such wordlist exists'
  else
    # check if wordlist is in use
    @task_list = Tasks.all(wl_id: @wordlist.id)
    if !@task_list.empty?
      flash[:error] = 'This word list is associated with a task, it cannot be deleted.'
      redirect to ('/wordlists/list')
    end

    # remove from filesystem
    File.delete(@wordlist.path)

    # delete from db
    @wordlist.destroy
  end
  redirect to('/wordlists/list')
end

post '/wordlists/upload/' do
  varWash(params)
  if !params[:file] || params[:file].nil?
    flash[:error] = 'You must specify a file.'
    redirect to('/wordlists/add')
  end
  if !params[:name] || params[:name].empty?
    flash[:error] = 'You must specify a name for your wordlist.'
    redirect to('/wordlists/add')
  end

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

##### Hash Lists ###########

get '/hashfiles/list' do
  @customers = Customers.all
  @hashfiles = Hashfiles.all

  haml :hashfile_list
end

get '/hashfiles/delete' do
  varWash(params)
  @hashfile = Hashfiles.first(id: params[:hashfile_id])
  @hashfile.destroy() unless @hashfile.nil?

  flash[:success] = 'Successfuly removed hashfile.'

  redirect to('/hashfiles/list')
end

############################

##### Purge Data ###########

get '/purge' do
  varWash(params)
  # find all customer ids defined in targets
  @customersids = Targets.all(fields: [:customer_id], unique: true)

  @total_target_count = 0
  @total_cracked_count = 0
  # count all hashes not associated with an active customer
  @customersids.each do |custid|
    total_targets = Targets.count(:customer_id.not => custid.customerid)
    total_cracked = Targets.count(:customer_id.not => custid.customerid, :cracked => 1)
    @total_target_count = @total_target_count + total_targets
    @total_cracked_count = @total_cracked_count + total_cracked
  end

  haml :purge
end

post '/purge' do
  varWash(params)
  # delete all targets no associated with an active customer
  @customersids = Targets.all(fields: [:customer_id], unique: true)
  @customersids.each do |custid|
    @targets = Targets.all(:customer_id.not => custid.customer_id)
    @targets.destroy
  end

  redirect to('/purge')
end

############################

##### Analysis #############

# displays analytics for a specific client, job
get '/analytics' do
  varWash(params)

  @custid = params[:custid]
  #@jobid = params[:jobid]
  @hashfile_id = params[:hf_id]
  @button_select_customers = Customers.all

  if params[:custid] && !params[:custid].empty?
    @button_select_hashfiles = Hashfiles.all(customer_id: params[:custid])
  end

  if params[:custid] && !params[:custid].empty?
    @customers = Customers.first(id: params[:custid])
  else
    @customers = Customers.all
  end

  if params[:custid] && !params[:custid].empty?
#    if params[:jobid] && !params[:jobid].empty?
    if params[:hf_id] && !params[:hf_id].empty?
      @hashfiles = Hashfiles.first(id: params[:hf_id])
    else
      @hashfiles = Hashfiles.all
    end
  end

  # get results of specific customer if custid is defined
  if params[:custid] && !params[:custid].empty?
    # if we have a job
    # if we have a hashfile
    if params[:hf_id] && !params[:hf_id].empty?
      # Used for Total Hashes Cracked doughnut: Customer: Hashfile
      @cracked_pw_count = Targets.count(customer_id: params[:custid], hashfile_id: params[:hf_id], cracked: 1)
      @uncracked_pw_count = Targets.count(customer_id: params[:custid], hashfile_id: params[:hf_id], cracked: 0)

      # Used for Total Accounts table: Customer: Hashfile
      @total_accounts = Targets.count(customer_id: params[:custid], hashfile_id: params[:hf_id])

      # Used for Total Unique Users and originalhashes Table: Customer: Hashfile
      @total_users_originalhash = Targets.all(fields: [:username, :originalhash], customer_id: params[:custid], hashfile_id: params[:hf_id])

      # Used for Total Run Time: Customer: Job
      @total_run_time = Jobtasks.sum(:run_time, conditions: {:job_id => params[:jobid]})

      # make list of unique hashes
      unique_hashes = Set.new
      @total_users_originalhash.each do |entry|
        unique_hashes.add(entry.originalhash)
      end

      hashes = []
      # create array of all hashes to count dups
      @total_users_originalhash.each do |uh|
        unless uh.originalhash.nil?
          hashes << uh.originalhash unless uh.originalhash.length == 0
        end
      end

      @duphashes = {}
      # count dup hashes
      hashes.each do |hash|
        if @duphashes[hash].nil?
          @duphashes[hash] = 1
        else
          @duphashes[hash] += 1
        end
      end
      # this will only display top 10 hash/passwords shared by users
      @duphashes = Hash[@duphashes.sort_by { |k, v| -v }[0..20]]
      # this will only display all hash/passwords shared by users
      #@duphashes = Hash[@duphashes.sort_by { |k, v| -v }]

      users_same_password = []
      @password_users ={}
      # for each unique password hash find the users and their plaintext
      @duphashes.each do |hash|
        dups = Targets.all(fields: [:username, :plaintext, :cracked], hashfile_id: params[:hf_id], customer_id: params[:custid], originalhash: hash[0])
        # for each user with the same password hash add user to array
        dups.each do |d|
          if !d.username.nil?
            users_same_password << d.username
            #puts "user: #{d.username} hash: #{hash[0]} password: #{d.plaintext}"
          else
            users_same_password << "NULL"
          end
          if d.cracked
            hash[0] = d.plaintext
          end
        end
        # assign array of users to hash of similar password hashes
        if users_same_password.length > 1
          @password_users[hash[0]] = users_same_password
        end
        users_same_password = []
      end

    else
      # Used for Total Hashes Cracked doughnut: Customer
      @cracked_pw_count = Targets.count(customer_id: params[:custid], cracked: 1)
      @uncracked_pw_count = Targets.count(customer_id: params[:custid], cracked: 0)

      # Used for Total Accounts Table: Customer
      @total_accounts = Targets.count(customer_id: params[:custid])

      # Used for Total Unique Users and original hashes Table: Customer
      @total_users_originalhash = Targets.all(fields: [:username, :originalhash], customer_id: params[:custid])

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
  varWash(params)

  @counts = []
  @passwords = {}

  if params[:custid] && !params[:custid].empty?
#    if params[:jobid] && !params[:jobid].empty?
    if params[:hf_id] && !params[:hf_id].empty?
      @cracked_results = Targets.all(fields: [:plaintext], customer_id: params[:custid], hashfile_id: params[:hf_id], cracked: true)
    else
      @cracked_results = Targets.all(fields: [:plaintext], customer_id: params[:custid], cracked: true)
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
  varWash(params)

  plaintext = []
  if params[:custid] && !params[:custid].empty?
#    if params[:jobid] && !params[:jobid].empty?
    if params[:hf_id] && !params[:hf_id].empty?
      @cracked_results = Targets.all(fields: [:plaintext], customer_id: params[:custid], hashfile_id: params[:hf_id], cracked: true)
    else
      @cracked_results = Targets.all(fields: [:plaintext], customer_id: params[:custid], cracked: true)
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
  varWash(params)

  plaintext = []
  if params[:custid] && !params[:custid].empty?
#    if params[:jobid] && !params[:jobid].empty?
    if params[:hf_id] && !params[:hf_id].empty?
      @cracked_results = Targets.all(fields: [:plaintext], customer_id: params[:custid], hashfile_id: params[:hf_id], cracked: true)
    else
      @cracked_results = Targets.all(fields: [:plaintext], customer_id: params[:custid], cracked: true)
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
  varWash(params)
  @customers = Customers.all

  if params[:value].nil? || params[:value].empty?
    flash[:error] = "Please provide a search term"
    redirect to('/search')
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
  hashfile_id = @job.hashfile_id
  @targets = Targets.first(hashfile_id: hashfile_id)
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
        p "CLEANED: " + params[key]
      end
      if params[key].is_a?(Array)
        params[key] = cleanArray(params[key])
      end
    end
  end

  def cleanString(text)
    p "BEFORE: " + text unless text.nil?
    return text.gsub(/[<>'"()\/\\]*/i, '') unless text.nil?
    p "CLEANED: " + text unless text.nil?
  end

  def cleanArray(array)
    clean_array = []
    array.each do |entry|
      clean_array.push(cleanString(entry))
    end
    return clean_array
  end
end
