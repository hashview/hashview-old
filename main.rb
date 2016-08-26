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

############################

##### Home controllers #####

get '/home' do
  redirect to('/') if !valid_session?
  @results = `ps awwux | grep -i Hashcat | egrep -v "(grep|screen|SCREEN|resque|^$)" | grep -v sudo`
  @jobs = Jobs.all
  @jobtasks = Jobtasks.all
  @tasks = Tasks.all
  @recentlycracked = Targets.all(:limit => 10, :cracked => 1, :order => [:updated_at.desc])

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

  @jobs.each do | j |
    if j.status
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

  haml :home
end

get '/register' do
  haml :register
end

############################

### customer controllers ###

get '/customer/list' do
  redirect to('/') if !valid_session?

  @customers = Customers.all

  haml :customer_list
end

get '/customer/create' do
  redirect to('/') if !valid_session?

  haml :customer_edit
end

post '/customer/create' do

  customer = Customers.new
  customer.name = params[:name]
  customer.description = params[:desc]
  customer.save

  redirect to ('customer/list')
end

get '/customer/edit/:id' do
  redirect to('/') if !valid_session?

  @customer = Customers.first(:id => params[:id])

  haml :customer_edit 
end

post '/customer/edit/:id' do
  redirect to('/') if !valid_session?

  customer = Customers.first(:id => params[:id])
  customer.name = params[:name]
  customer.description = params[:desc]
  customer.save

  redirect to ('customer/list')
end

get '/customer/delete/:id' do
  redirect to('/') if !valid_session?

  customer = Customers.first(:id => params[:id])
  customer.destroy

  jobs = Jobs.all(:customer_id => params[:id])
  if !jobs.empty?
    jobs.destroy
  end

  targets = Targets.all(:customerid => params[:id])
  if !targets.empty?
    targets.destroy
  end

  redirect to ('/customer/list')
end

############################

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

  tasks = Tasks.all()
  if tasks.empty?
    warning("You need to have tasks before starting a job")
  end

  @rules = []
  # list wordlists that can be used
  Dir.foreach('control/rules/') do |item|
    next if item == '.' || item == '..'
      @rules << item
  end

  @wordlists = Wordlists.all()

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

  @targets_cracked = Hash.new  
  @customer_names = Hash.new

  @jobs = Jobs.all
  @tasks = Tasks.all
  @jobtasks = Jobtasks.all
  # @targets = Targets.all
  # @customers = Customers.all
  
  @jobs.each do |entry|
    @targets_cracked[entry.id] = Targets.count(:jobid => [entry.id], :cracked => 1)
  end
 
  @jobs.each do |entry|
    @customers = Customers.first(:id => [entry.customer_id])
    p "CUSTOMERS: " + @customers.to_s
    @customer_names[entry.customer_id] = @customers.name
  end

  haml :job_list
end

get '/job/delete/:id' do
  redirect to('/') if !valid_session?

  @job = Jobs.first(:id => params[:id])
  if !@job
    return 'No such job exists.'
  else
    @job.destroy
  end

  redirect to('/job/list')
end

get '/job/create' do
  redirect to('/') if !valid_session?

  @customers = Customers.all
  if @customers.empty?
    redirect to('/customer/create')
  end

  @tasks = Tasks.all
  if @tasks.empty?
    redirect to('/task/create')
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

post '/job/create' do
  redirect to('/') if !valid_session?

  if !params[:tasks]
    return "you must assign tasks to your job"
  end

  # create new job
  job = Jobs.new
  job.name = params[:name]
  job.last_updated_by = get_username
  job.customer_id = params[:customer]
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

  @job = Jobs.first(:id => params[:id])
  customer_id = @job.customer_id

  # we do this to speed up the inserts for large hash imports
  # http://www.sqlite.org/faq.html#q19
  # for some reason this doesnt persist so it is placed here, closest to the commits/inserts
  adapter = DataMapper::repository(:default).adapter
  adapter.select("PRAGMA synchronous = OFF;")

  if not import_hash(hashArray, customer_id, params[:id], filetype, hashtype)
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

  redirect to('/home')
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

  if @settings.maxtasktime.nil?
    warning("Max task time must be defined in seconds (864000 is 10 days)")
  end

  haml :global_settings
end

post '/settings' do
  redirect to('/') if !valid_session?

  values = request.POST

  @settings = Settings.first()

  if @settings == nil
    # create settings for the first time
    # set max task time if none is provided
    if @setttings.maxtasktime.nil?
      values["maxtasktime"] = "864000"
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
    # check if wordlist is in use
    tasks = Tasks.all(:wl_id => @wordlist.id)
    if tasks
      return "This word list is associated with a task, it cannot be deleted"
    end

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

##### Purge Data ###########

get '/purge' do
  redirect to('/') if !valid_session?

  @job_cracked = Hash.new
  @job_total = Hash.new
  @job_id_name = Hash.new
  @target_jobids = []
  @all_cracked = 0
  @all_total = 0
  @targets = Targets.all(:fields => [:jobid], :unique => true) 
  @targets.each do | entry |
    @target_jobids.push(entry.jobid)
  end

  @jobs = Jobs.all()
  @jobs.each do | entry |
    @job_id_name[entry.id] = entry.name
  end

  @target_jobids.each do | entry |
    @job_cracked[entry] = Targets.count(:jobid => [entry], :cracked => 1)
    @all_cracked = @all_cracked + @job_cracked[entry]
    #p "ALL CRACKED: " + @all_cracked.to_s
    @job_total[entry] = Targets.count(:jobid => [entry])
    @all_total = @all_total + @job_total[entry]
    #p "ALL TOTAL: " + @all_total.to_s
  end
    
  haml :purge

end

get '/purge/:id' do
  redirect to('/') if !valid_session?

  if params[:id] == 'all'
    @targets = Targets.all()
    @targets.destroy
  else
    @targets = Targets.all(:jobid => params[:id])
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

  if params[:custid] and ! params[:custid].empty?
    @button_select_jobs = Jobs.all(:customer_id => params[:custid])
  end

  if params[:custid] and ! params[:custid].empty?
    @customers = Customers.first(:id => params[:custid])
  else
    @customers = Customers.all
  end

  if params[:custid] and ! params[:custid].empty?
    if params[:jobid] and ! params[:jobid].empty?
      @jobs = Jobs.first(:id => params[:jobid])
    else
      @jobs = Jobs.all
    end
  end

  # get results of specific customer if custid is defined
  if params[:custid] and ! params[:custid].empty?
    # if we have a job
    if params[:jobid] and ! params[:jobid].empty?
      # Used for Total Hashes Cracked doughnut: Customer: Job
      @cracked_pw_count = Targets.count(:customerid => params[:custid], :jobid => params[:jobid], :cracked => 1)
      @uncracked_pw_count = Targets.count(:customerid => params[:custid], :jobid => params[:jobid], :cracked => 0)
      
      # Used for Total Accounts table: Customer: Job
      @total_accounts = Targets.count(:customerid => params[:custid], :jobid => params[:jobid])

      # Used for Total Unique Users and originalhashes Table: Customer: Job
      @total_users_originalhash = Targets.all(:fields => [:username, :originalhash], :customerid => params[:custid], :jobid => params[:jobid])

    else
      # Used for Total Hashes Cracked doughnut: Customer
      @cracked_pw_count = Targets.count(:customerid => params[:custid], :cracked => 1)
      @uncracked_pw_count = Targets.count(:customerid => params[:custid], :cracked => 0)

      # Used for Total Accounts Table: Customer
      @total_accounts = Targets.count(:customerid => params[:custid])

      # Used for Total Unique Users and original hashes Table: Customer
      @total_users_originalhash = Targets.all(:fields => [:username, :originalhash], :customerid => params[:custid])
    end
  else
    # Used for Total Hash Cracked Doughnut: Total
    @cracked_pw_count = Targets.count(:cracked => 't')
    @uncracked_pw_count = Targets.count(:cracked => 'f')

    # Used for Total Accounts Table: Total
    @total_accounts = Targets.count

    # Used for Total Unique Users and originalhashes Tables: Total
    @total_users_originalhash = Targets.all(:fields => [:username, :originalhash])
  end

  @passwords = @cracked_results.to_json

  # Unique Usernames
  @total_unique_users_count = Set.new

  # Unique Passwords
  @total_unique_originalhash_count = Set.new
  
  @total_users_originalhash.each do | entry |
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

  if params[:custid]  and ! params[:custid].empty?
    if params[:jobid] and ! params[:jobid].empty?
      @cracked_results = Targets.all(:customerid => params[:custid], :jobid => params[:jobid], :cracked => true)
    else
      @cracked_results = Targets.all(:customerid => params[:custid], :cracked => true)
    end
  else
    @cracked_results = Targets.all(:cracked => true)
  end

  @cracked_results.each do |crack|
    if ! crack.plaintext.nil?
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
    @counts << {:length => key, :count => value}
  end

  return @counts.to_json
end

# callback for d3 graph displaying top 10 passwords
get '/analytics/graph2' do
  plaintext = []
  if params[:custid] and ! params[:custid].empty?
    if params[:jobid] and ! params[:jobid].empty?
      @cracked_results = Targets.all(:customerid => params[:custid], :jobid => params[:jobid], :cracked => true)
    else
      @cracked_results = Targets.all(:customerid => params[:custid], :cracked => true)
    end
  else
    @cracked_results = Targets.all(:cracked => true)
  end
  @cracked_results.each do |crack|
    if ! crack.plaintext.nil?
      unless crack.plaintext.length == 0
        plaintext << crack.plaintext
      end
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
  @top10passwords = @top10passwords.sort_by {|key, value| value}.reverse.to_h
  # we only need top 10
  @top10passwords = Hash[@top10passwords.sort_by { |k,v| -v}[0..9]]
  # convert to array of json objects for d3
  @top10passwords.each do |key, value|
    @toppasswords << {:password => key, :count => value}
  end

  return @toppasswords.to_json
end

############################

##### search ###############

get '/search' do
  redirect to('/') if !valid_session?
  haml :search
end

post '/search' do
  redirect to('/') if !valid_session?
 
  @plaintexts = Targets.all(:originalhash => params[:hash])   
  haml :search_post

end

############################

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

  # we assign and write output file before hashcat.
  # if hashcat creates its own output it does so with
  # elvated permissions and we wont be able to read it
  crack_file = "control/outfiles/hc_cracked_" + @job.id.to_s + "_" + @task.id.to_s + ".txt"
  File.open(crack_file, "w")

  if attackmode == "3"
    cmd = "sudo " + hcbinpath + " -m " + hashtype + " --potfile-disable" + " --runtime=" + maxtasktime + " --outfile-format 3 " + " --outfile " + crack_file + " " + " -a " + attackmode + " " + target_file
  elsif attackmode == "0"
    if @task.hc_rule == "none"
      cmd = "sudo " + hcbinpath + " -m " + hashtype + " --potfile-disable" + " --outfile-format 3 " + " --outfile " + crack_file + " " + target_file + " " + wordlist.path
    else
      cmd = "sudo " + hcbinpath + " -m " + hashtype + " --potfile-disable" + " --outfile-format 3 " + " --outfile " + crack_file + " " +  " -r " + "control/rules/" + @task.hc_rule + " " + target_file + " " + wordlist.path
    end
  end
  p cmd
  return cmd
end

# Check if kraken has a job running
def is_krakenbusy?
  @results = `ps awwux | grep -i Hashcat | egrep -v "(grep|^$)" | grep -v sudo`
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

  def warning(txt)
    if @warnings != nil
      @warnings << txt
    else
      @warnings = []
      @warnings << txt
    end
    return @warnings
  end

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
