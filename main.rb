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

get '/home' do
  @results = `ps awwux | grep -i Hashcat | egrep -v "(grep|screen|SCREEN|resque|^$)"`
  @jobs = Jobs.all(:order => [:id.asc])
  @jobtasks = Jobtasks.all
  @tasks = Tasks.all

  @recentlycracked = Hashes.all(fields: [:originalhash, :plaintext], cracked: 1, limit: 10, :order => [:lastupdated.desc])

  @customers = Customers.all
  @active_jobs = Jobs.all(fields: [:id, :status], status: 'Running') | Jobs.all(fields: [:id, :status], status: 'Importing') 

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

  @jobs.each do |j|
    if j.status == 'Running'
      # gather info for statistics

      @hash_ids = Array.new
      Hashfilehashes.all(fields: [:hash_id], hashfile_id: j.hashfile_id).each do |entry|
        @hash_ids.push(entry.hash_id)
      end
 
      @alltargets = Hashes.count(id: @hash_ids)
      @crackedtargets = Hashes.count(id: @hash_ids, cracked: 1)

      @progress = (@crackedtargets.to_f / @alltargets.to_f) * 100
      # parse a hashcat status file
      @hashcat_status = hashcatParser('control/outfiles/hcoutput_' + j.id.to_s + '.txt')
    end
  end

  haml :home
end

############################

### customer controllers ###

get '/customers/list' do
  @customers = Customers.all
  @total_jobs = []
  @total_hashfiles = []

  @customers.each do |customer|
    @total_jobs[customer.id] = Jobs.count(customer_id: customer.id)
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

  # @hashfilehashes = Hashfilehashes.all(hashfile_id:
  # Need to select/identify what hashfiles are associated with this customer then remove them from hashfilehashes 

  @hashfiles = Hashfiles.all(customer_id: params[:id])
  @hashfiles.destroy unless @hashfiles.nil?

  redirect to('/customers/list')
end

post '/customers/upload/hashfile' do
  varWash(params)

  if params[:hashfile_name].nil? || params[:hashfile_name].empty?
    flash[:error] = 'You must specificy a name for this hash file.'
    redirect to("/jobs/assign_hashfile?customer_id=#{params[:customer_id]}&job_id=#{params[:job_id]}")
  end

  if params[:file].nil? || params[:file].empty?
    flash[:error] = 'You must specify a hashfile.'
    redirect to("/jobs/assign_hashfile?customer_id=#{params[:customer_id]}&job_id=#{params[:job_id]}")
  end

  @job = Jobs.first(id: params[:job_id])
  return 'No such job exists' unless @job

  # temporarily save file for testing
  hash = rand(36**8).to_s(36)
  hashfile = "control/hashes/hashfile_upload_job_id-#{@job.id}-#{hash}.txt"

  # Parse uploaded file into an array
  hash_array = []
  whole_file_as_string_object = params[:file][:tempfile].read
  File.open(hashfile, 'w') { |f| f.write(whole_file_as_string_object) }
  whole_file_as_string_object.each_line do |line|
    hash_array << line
  end

  # save location of tmp hash file
  hashfile = Hashfiles.new
  hashfile.name = params[:hashfile_name]
  hashfile.customer_id = params[:customer_id]
  hashfile.hash_str = hash
  hashfile.save

  @job.save

  redirect to("/customers/upload/verify_filetype?customer_id=#{params[:customer_id]}&job_id=#{params[:job_id]}&hashid=#{hashfile.id}")
end

get '/customers/upload/verify_filetype' do
  varWash(params)

  hashfile = Hashfiles.first(id: params[:hashid])

  @filetypes = detectHashfileType("control/hashes/hashfile_upload_job_id-#{params[:job_id]}-#{hashfile.hash_str}.txt")
  @job = Jobs.first(id: params[:job_id])
  haml :verify_filetypes
end

post '/customers/upload/verify_filetype' do
  varWash(params)

  redirect to("/customers/upload/verify_hashtype?customer_id=#{params[:customer_id]}&job_id=#{params[:job_id]}&hashid=#{params[:hashid]}&filetype=#{params[:filetype]}")
end

get '/customers/upload/verify_hashtype' do
  varWash(params)

  hashfile = Hashfiles.first(id: params[:hashid])

  @hashtypes = detectHashType("control/hashes/hashfile_upload_job_id-#{params[:job_id]}-#{hashfile.hash_str}.txt", params[:filetype])
  @job = Jobs.first(id: params[:job_id])
  haml :verify_hashtypes
end

post '/customers/upload/verify_hashtype' do
  varWash(params)

  if !params[:filetype] || params[:filetype].nil?
    flash[:error] = 'You must specify a valid hashfile type.'
    redirect to("/customers/upload/verify_hashtype?customer_id=#{params[:customer_id]}&job_id=#{params[:job_id]}&hashid=#{params[:hashid]}&filetype=#{params[:filetype]}")
  end

  filetype = params[:filetype]

  hashfile = Hashfiles.first(id: params[:hashid])

  if params[:hashtype] == '99999'
    hashtype = params[:manualHash]
  else
    hashtype = params[:hashtype]
  end

  hash_file = "control/hashes/hashfile_upload_job_id-#{params[:job_id]}-#{hashfile.hash_str}.txt"

  hash_array = []
  File.open(hash_file, 'r').each do |line|
    hash_array << line
  end

  @job = Jobs.first(id: params[:job_id])
  customer_id = @job.customer_id
  @job.hashfile_id = hashfile.id
  @job.save

  unless importHash(hash_array, hashfile.id, filetype, hashtype)
    flash[:error] = 'Error importing hashes'
    redirect to("/customers/upload/verify_hashtype?customer_id=#{params[:customer_id]}&job_id=#{params[:job_id]}&hashid=#{params[:hashid]}&filetype=#{params[:filetype]}")
  end

  previously_cracked_cnt = repository(:default).adapter.select('SELECT COUNT(h.originalhash) FROM hashes h LEFT JOIN hashfilehashes a ON h.id = a.hash_id WHERE (a.hashfile_id = ? AND h.cracked = 1)', hashfile.id)[0].to_s
  total_cnt = repository(:default).adapter.select('SELECT COUNT(h.originalhash) FROM hashes h LEFT JOIN hashfilehashes a ON h.id = a.hash_id WHERE a.hashfile_id = ?', hashfile.id)[0].to_s

  unless total_cnt.nil?
    flash[:success] = 'Successfully uploaded ' + total_cnt + ' hashes.'
  end

  unless previously_cracked_cnt.nil?
    flash[:success] = previously_cracked_cnt + ' have already been cracked!'
  end

  # Delete file, no longer needed
  File.delete(hash_file)

  if params[:edit]
    redirect to("/jobs/assign_tasks?job_id=#{params[:job_id]}&edit=1")
  else
    redirect to("/jobs/assign_tasks?job_id=#{params[:job_id]}")
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
    flash[:error] = 'Passwords do not match.'
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

  @job_tasks = Jobtasks.all(task_id: params[:id])
  unless @job_tasks.empty?
    flash[:error] = 'That task is currently used in a job.'
    redirect to('/tasks/list')
  end

  @task = Tasks.first(id: params[:id])
  @task.destroy if @task

  redirect to('/tasks/list')
end

get '/tasks/edit/:id' do
  varWash(params)
  @task = Tasks.first(id: params[:id])
  @wordlists = Wordlists.all
  @settings = Settings.first

  if @task.hc_attackmode == 'combinator'
    @combinator_wordlists = @task.wl_id.split(',')
    if @task.hc_rule =~ /--rule-left=(.*) --rule-right=(.*)/
      @combinator_left_rule = $1
      @combinator_right_rule = $2
    elsif @task.hc_rule =~ /--rule-left=(.*)/
      @combinator_left_rule = $1
    elsif @task.hc_rule =~ /--rule-right=(.*)/
      @combinator_right_rule = $1
    end
  end

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

  # must have two word lists
  if params[:attackmode] == 'combinator'
    wordlist_count = 0
    wordlist_list = ''
    rule_list = ''
    @wordlists = Wordlists.all
    @wordlists.each do |wordlist_check|
      params.keys.each do |key|
        if params[key] == 'on' && key == "combinator_wordlist_#{wordlist_check.id}"
          if wordlist_list == ''
            wordlist_list = wordlist_check.id.to_s + ','
          else
            wordlist_list = wordlist_list + wordlist_check.id.to_s
          end
          wordlist_count = wordlist_count + 1
        end
      end
    end

    if wordlist_count != 2
      flash[:error] = 'You must specify at exactly 2 wordlists.'
      redirect to("/tasks/edit/#{params[:id]}")
    end

    if params[:combinator_left_rule] && !params[:combinator_left_rule].empty? && params[:combinator_right_rule] && !params[:combinator_right_rule].empty?
      rule_list = '--rule-left=' + params[:combinator_left_rule] + ' --rule-right=' + params[:combinator_right_rule]
    elsif params[:combinator_left_rule] && !params[:combinator_left_rule].empty?
      rule_list = '--rule-left=' + params[:combinator_left_rule]
    elsif params[:combinator_right_rule] && !params[:combinator_right_rule].empty?
      rule_list = '--rule-right=' + params[:combinator_right_rule]
    else
      rule_list = ''
    end
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
  elsif params[:attackmode] == 'combinator'
    task.wl_id = wordlist_list 
    task.hc_rule = rule_list
    task.hc_mask = 'NULL'
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

  @tasks = Tasks.all(name: params[:name])
  unless @tasks.nil?
    @tasks.each do |task|
      if task.name == params[:name]
        flash[:error] = 'Name already in use, pick another'
        redirect to('/tasks/create')
      end
    end
  end

  wordlist = Wordlists.first(id: params[:wordlist])

  # mask field cannot be empty
  if params[:attackmode] == 'maskmode'
    if !params[:mask] || params[:mask].empty?
      flash[:error] = 'Mask field cannot be left empty'
      redirect to('/tasks/create')
    end
  end

  # must have two word lists
  if params[:attackmode] == 'combinator'
    wordlist_count = 0
    wordlist_list = ''
    rule_list = ''
    @wordlists = Wordlists.all
    @wordlists.each do |wordlist_check|
      params.keys.each do |key|
        if params[key] == 'on' && key == "combinator_wordlist_#{wordlist_check.id}"
          if wordlist_list == ''
            wordlist_list = wordlist_check.id.to_s + ','
          else
            wordlist_list = wordlist_list + wordlist_check.id.to_s
          end
          wordlist_count = wordlist_count + 1
        end
      end
    end

    if wordlist_count != 2
      flash[:error] = 'You must specify at exactly 2 wordlists.'
      redirect to('/tasks/create')
    end

    if params[:combinator_left_rule] && !params[:combinator_left_rule].empty? && params[:combinator_right_rule] && !params[:combinator_right_rule].empty?
      rule_list = '--rule-left=' + params[:combinator_left_rule] + ' --rule-right=' + params[:combinator_right_rule]
    elsif params[:combinator_left_rule] && !params[:combinator_left_rule].empty?
      rule_list = '--rule-left=' + params[:combinator_left_rule]
    elsif params[:combinator_right_rule] && !params[:combinator_right_rule].empty?
      rule_list = '--rule-right=' + params[:combinator_right_rule]
    else
      rule_list = ''
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
  elsif params[:attackmode] == 'combinator'
    task.wl_id = wordlist_list
    task.hc_rule = rule_list
  end
  task.save

  flash[:success] = "Task #{task.name} successfully created."

  redirect to('/tasks/list')
end

############################

##### job controllers #####

get '/jobs/list' do
  @targets_cracked = {}
  @customer_names = {}
  @wordlist_id_to_name = {}

  @jobs = Jobs.all(order: [:id.desc])
  @tasks = Tasks.all
  @jobtasks = Jobtasks.all
  @wordlists = Wordlists.all

  @wordlists.each do |wordlist|
    @wordlist_id_to_name[wordlist.id.to_s] = wordlist.name
  end

  @jobs.each do |job|
    @customers = Customers.first(id: [job.customer_id])
    @customer_names[job.customer_id] = @customers.name
  end

  haml :job_list
end

get '/jobs/delete/:id' do
  varWash(params)

  @job = Jobs.first(id: params[:id])
  unless @job
    flash[:error] = 'No such job exists.'
    redirect to('/jobs/list')
  else
    if @job.status == 'Running' || @job.status == 'Importing'
      flash[:error] = 'Failed to Delete Job. A task is currently running.'
      redirect to('/jobs/list')
    end
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
  @job = Jobs.first(id: params[:job_id])

  haml :job_edit
end

post '/jobs/create' do
  varWash(params)

  if !params[:job_name] || params[:job_name].empty?
    flash[:error] = 'You must provide a name for your job.'
    if params[:edit] == '1'
      redirect to("/jobs/create?customer_id=#{params[:customer_id]}&job_id=#{params[:job_id]}&edit=1")
    else
      redirect to('/jobs/create')
    end
  end

  if !params[:customer] || params[:customer].empty?
    if !params[:cust_name] || params[:cust_name].empty?
      flash[:error] = 'You must provide a customer for your job.'
      if params[:edit] == '1'
        redirect to("/jobs/create?customer_id=#{params[:customer_id]}&job_id=#{params[:job_id]}&edit=1")
      else
        redirect to('/jobs/create')
      end
    end
  end

  if params[:customer] && params[:customer] == 'add_new'
    if !params[:cust_name] || params[:cust_name].empty?
      flash[:error] = 'You must provide a customer name.'
      if params[:edit] == '1'
        redirect to("/jobs/create?customer_id=#{params[:customer_id]}&job_id=#{params[:job_id]}&edit=1")
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
    customer_id = customer.id
  else
    customer_id = params[:customer]
  end

  # create new or update existing job
  if params[:edit] == '1'
    job = Jobs.first(id: params[:job_id])
  else
    job = Jobs.new
  end
  job.name = params[:job_name]
  job.last_updated_by = getUsername
  job.customer_id = customer_id

  if params[:notify] == 'on'
    job.notify_completed = '1'
  else
    job.notify_completed = '0'
  end
  job.save

  if params[:edit] == '1'
    redirect to("/jobs/assign_hashfile?customer_id=#{customer_id}&job_id=#{job.id}&edit=1")
  else
    redirect to("/jobs/assign_hashfile?customer_id=#{customer_id}&job_id=#{job.id}")
  end
end

get '/jobs/assign_hashfile' do
  varWash(params)

  @hashfiles = Hashfiles.all(customer_id: params[:customer_id])
  @customer = Customers.first(id: params[:customer_id])

  @cracked_status = Hash.new
  @hashfiles.each do |hash_file|
    @hash_ids = Set.new
    Hashfilehashes.all(fields: [:hash_id], hashfile_id: hash_file.id).each do |entry|
      @hash_ids.add(entry.hash_id)
    end

    hash_file_cracked_count = Hashes.count(id: @hash_ids.to_a, cracked: 1)
    hash_file_total_count = Hashes.count(id: @hash_ids.to_a)
    @cracked_status[hash_file.id] = hash_file_cracked_count.to_s + "/" + hash_file_total_count.to_s
  end

  @job = Jobs.first(id: params[:job_id])
  return 'No such job exists' unless @job

  haml :assign_hashfile
end

post '/jobs/assign_hashfile' do
  varWash(params)

  if params[:hash_file] != 'add_new'
    job = Jobs.first(id: params[:job_id])
    job.hashfile_id = params[:hash_file]
    job.save
  end

  if params[:edit] == '1'
    job = Jobs.first(id: params[:job_id])
    job.hashfile_id = params[:hash_file]
    job.save
  end

  if params[:edit]
    redirect to("/jobs/assign_tasks?job_id=#{params[:job_id]}&customer_id=#{params[:customer_id]}&hashid=#{params[:hash_file]}&edit=1")
  else
    redirect to("/jobs/assign_tasks?job_id=#{params[:job_id]}&customer_id=#{params[:customer_id]}&hashid=#{params[:hash_file]}")
  end
end

get '/jobs/assign_tasks' do
  varWash(params)

  @job = Jobs.first(id: params[:job_id])
  @jobtasks = Jobtasks.all(job_id: params[:job_id])
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
      redirect to("/jobs/assign_tasks?job_id=#{params[:job_id]}&customer_id=#{params[:customer_id]}&hashid=#{params[:hash_file]}")
    end
  end

  job = Jobs.first(id: params[:job_id])
  job.status = 'Stopped'
  job.save

  # assign tasks to the job
  if params[:tasks] && !params[:tasks].nil?
    assignTasksToJob(params[:tasks], job.id)
  end

  # Resets jobtasks tables
  if params[:edit] && !params[:edit].nil?
    @jobtasks = Jobtasks.all(job_id: params[:job_id])
    @jobtasks.each do |jobtask|
      jobtask.status = 'Queued'
      jobtask.save
    end
  end

  flash[:success] = 'Successfully created job.'
  redirect to('/jobs/list')
end

get '/jobs/start/:id' do
  varWash(params)

  tasks = []
  @job = Jobs.first(id: params[:id])
  unless @job
    flash[:error] = 'No such job exists.'
    redirect to('/jobs/list')
  else
    @jobtasks = Jobtasks.all(job_id: params[:id])
    unless @jobtasks
      flash[:error] = 'This job has no tasks to run.'
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
      Resque.enqueue(Jobq, jt.id, cmd)
    end
  end

  if @job.status == 'Completed'
    flash[:error] = 'All tasks for this job have been completed. To prevent overwriting your results, you will need to create a new job with the same tasks in order to rerun the job.'
    redirect to('/jobs/list')
  end

  redirect to('/home')
end

get '/jobs/stop/:id' do
  varWash(params)

  @job = Jobs.first(id: params[:id])
  @jobtasks = Jobtasks.all(job_id: params[:id])

  @job.status = 'Canceled'
  @job.save

  @jobtasks.each do |task|
    # do not stop tasks if they have already been completed.
    # set all other tasks to status of Canceled
    if task.status == 'Queued'
      task.status = 'Canceled'
      task.save
      cmd = buildCrackCmd(@job.id, task.task_id)
      cmd = cmd + ' | tee -a control/outfiles/hcoutput_' + @job.id.to_s + '.txt'
      puts 'STOP CMD: ' + cmd
      Resque::Job.destroy('hashcat', Jobq, task.id, cmd)
    end
  end

  @jobtasks.each do |task|
    if task.status == 'Running'
      redirect to("/jobs/stop/#{task.job_id}/#{task.task_id}")
    end
  end

  redirect to('/jobs/list')
end

get '/jobs/stop/:job_id/:taskid' do
  varWash(params)

  # validate if running
  jt = Jobtasks.first(job_id: params[:job_id], task_id: params[:taskid])
  unless jt.status == 'Running'
    return 'That specific Job and Task is not currently running.'
  end
  # find pid
  pid = `ps -ef | grep hashcat | grep hc_cracked_#{params[:job_id]}_#{params[:taskid]}.txt | grep -v 'ps -ef' | grep -v 'sh \-c' | awk '{print $2}'`
  pid = pid.chomp

  # update jobtasks to "canceled"
  jt.status = 'Canceled'
  jt.save

  # Kill jobtask
  `kill -9 #{pid}`

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

  @job = Jobs.first(id: params[:job_id])
  unless @job
    flash[:error] = 'No such job exists.'
    redirect to('/jobs/list')
  else
    @jobtask = Jobtasks.first(id: params[:jobtaskid])
    @jobtask.destroy
  end

  redirect to("/jobs/assign_tasks?customer_id=#{params[:customer_id]}&job_id=#{params[:job_id]}&edit=1")
end

############################

##### Global Settings ######

get '/settings' do
  @settings = Settings.first

  @auth_types = %w(None, Plain, Login, cram_md5)

  if @settings && @settings.maxtasktime.nil?
    flash[:info] = 'Max task time must be defined in seconds (86400 is 1 day)'
  end

  haml :global_settings
end

post '/settings' do
  if params[:hcbinpath].nil? || params[:hcbinpath].empty?
    flash[:error] = 'You must set the path for your hashcat binary.'
    redirect('/settings')
  end

  if params[:maxtasktime].nil? || params[:maxtasktime].empty?
    flash[:error] = 'You must set a max task time.'
    redirect('/settings')
  end

  if params[:smtp_use_tls] == 'on'
    params[:smtp_use_tls] = '1'
  else
    params[:smtp_use_tls] = '0'
  end

  settings = Settings.first

  if settings.nil?
    settings = Settings.create
  end

  settings.hcbinpath = params[:hcbinpath] unless params[:hcbinpath].nil? || params[:hcbinpath].empty?
  settings.maxtasktime = params[:maxtasktime] unless params[:maxtasktime].nil? || params[:maxtasktime].empty?
  settings.smtp_server = params[:smtp_server] unless params[:smtp_server].nil? || params[:smtp_server].nil?
  settings.smtp_auth_type = params[:smtp_auth_type] unless params[:smtp_auth_type].nil? || params[:smtp_auth_type].empty?
  settings.smtp_use_tls = params[:smtp_use_tls] unless params[:smtp_use_tls].nil? || params[:smtp_use_tls].empty?
  settings.smtp_user = params[:smtp_user] unless params[:smtp_user].nil? || params[:smtp_user].empty?
  settings.smtp_pass = params[:smtp_pass] unless params[:smtp_pass].nil? || params[:smtp_pass].empty?
  settings.save

  flash[:success] = 'Settings updated successfully.'

  redirect to('/home')
end

############################

##### Downloads ############

get '/download' do
  varWash(params)

  if params[:customer_id] && !params[:customer_id].empty?
    if params[:hashfile_id] && !params[:hashfile_id].nil?

      # Until we can figure out JOIN statments, we're going to have to hack it
      @filecontents = Set.new
      Hashfilehashes.all(fields: [:id], hashfile_id: params[:hashfile_id]).each do |entry|
        #@hashfilehash_ids.add(entry.hash_id)
        if params[:type] == 'cracked' and Hashes.first(fields: [:cracked], id: entry.hash_id).cracked
          if entry.username.nil? # no username
            line = ''
          else
            line = entry.username + ':'
          end
          line = line + Hashes.first(fields: [:originalhash], id: entry.hash_id).originalhash
          line = line + ':' + Hashes.first(fields: [:plaintext], id: entry.hash_id, cracked: 1).plaintext
          @filecontents.add(line)
        elsif params[:type] == 'uncracked' and not Hashes.first(fields: [:cracked], id: entry.hash_id).cracked
          if entry.username.nil? # no username
            line = ''
          else
            line = entry.username + ':'
          end
          line = line + Hashes.first(fields: [:originalhash], id: entry.hash_id).originalhash
          @filecontents.add(line)
        end
      end
    else
      @filecontents = Set.new
      @hashfiles_ids = Hashfiles.all(fields: [:id], customer_id: params[:customer_id]).each do |hashfile|
        Hashfilehashes.all(fields: [:id], hashfile_id: hashfile.id).each do |entry|
          #@hashfilehash_ids.add(entry.hash_id)
          if params[:type] == 'cracked' and Hashes.first(fields: [:cracked], id: entry.hash_id).cracked
            if entry.username.nil? # no username
              line = ''
            else
              line = entry.username + ':'
            end
            line = line + Hashes.first(fields: [:originalhash], id: entry.hash_id).originalhash
            line = line + ':' + Hashes.first(fields: [:plaintext], id: entry.hash_id, cracked: 1).plaintext
            @filecontents.add(line)
          elsif params[:type] == 'uncracked' and not Hashes.first(fields: [:cracked], id: entry.hash_id).cracked
            if entry.username.nil? # no username
              line = ''
            else
              line = entry.username + ':'
            end
            line = line + Hashes.first(fields: [:originalhash], id: entry.hash_id).originalhash
            @filecontents.add(line)
          end
        end    
      end
    end
  else
    @filecontents = Set.new
    @hashfiles_ids = Hashfiles.all(fields: [:id]).each do |hashfile|
      Hashfilehashes.all(fields: [:id], hashfile_id: hashfile.id).each do |entry|
        #@hashfilehash_ids.add(entry.hash_id)
        if params[:type] == 'cracked' and Hashes.first(fields: [:cracked], id: entry.hash_id).cracked
          if entry.username.nil? # no username
            line = ''
          else
            line = entry.username + ':'
          end
          line = line + Hashes.first(fields: [:originalhash], id: entry.hash_id).originalhash
          line = line + ':' + Hashes.first(fields: [:plaintext], id: entry.hash_id, cracked: 1).plaintext
          @filecontents.add(line)
        elsif params[:type] == 'uncracked' and not Hashes.first(fields: [:cracked], id: entry.hash_id).cracked
          if entry.username.nil? # no username
            line = ''
          else
            line = entry.username + ':'
          end
          line = line + Hashes.first(fields: [:originalhash], id: entry.hash_id).originalhash
          @filecontents.add(line)
        end
      end
    end
  end

  # Write temp output file
  if params[:customer_id] && !params[:customer_id].empty?
    if params[:hashfile_id] && !params[:hashfile_id].nil?
      file_name = "found_#{params[:customer_id]}_#{params[:hashfile_id]}.txt" if params[:type] == 'cracked'
      file_name = "left_#{params[:customer_id]}_#{params[:hashfile_id]}.txt" if params[:type] == 'uncracked'
    else
      file_name = "found_#{params[:customer_id]}.txt" if params[:type] == 'cracked'
      file_name = "left_#{params[:customer_id]}.txt" if params[:type] == 'uncracked'
    end
  else
    file_name = 'found_all.txt' if params[:type] == 'cracked'
    file_name = 'left_all.txt' if params[:type] == 'uncracked'
  end

  file_name = 'control/outfiles/' + file_name

  File.open(file_name, 'w') do |f|
    @filecontents.each do |entry|
      f.puts entry
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
  if !@wordlist
    return 'no such wordlist exists'
  else
    # check if wordlist is in use
    @task_list = Tasks.all(wl_id: @wordlist.id)
    if !@task_list.empty?
      flash[:error] = 'This word list is associated with a task, it cannot be deleted.'
      redirect to('/wordlists/list')
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
  size = File.foreach(file_name).inject(0) { |c| c + 1 }

  wordlist = Wordlists.new
  wordlist.name = upload_name 
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
  @cracked_status = Hash.new
  @hashfiles.each do |hash_file|
    @hash_ids = Set.new
    Hashfilehashes.all(fields: [:hash_id], hashfile_id: hash_file.id).each do |entry|
      @hash_ids.add(entry.hash_id)
    end
    hash_file_cracked_count = Hashes.count(id: @hash_ids, cracked: 1)
    hash_file_total_count = Hashes.count(id: @hash_ids)
    @cracked_status[hash_file.id] = hash_file_cracked_count.to_s + "/" + hash_file_total_count.to_s
  end

  haml :hashfile_list
end

get '/hashfiles/delete' do
  varWash(params)
  
  @hashfilehashes = Hashfilehashes.all(hashfile_id: params[:hashfile_id])
  @hashfilehashes.destroy unless @hashfilehashes.empty?

  @hashfile = Hashfiles.first(id: params[:hashfile_id])
  @hashfile.destroy unless @hashfile.nil?

  @uncracked = Targets.all(hashfile_id: params[:hashfile_id], cracked: 0)
  @uncracked.destroy unless @uncracked.nil?

  flash[:success] = 'Successfuly removed hashfile.'

  redirect to('/hashfiles/list')
end

############################

##### Analysis #############

# displays analytics for a specific client, job
get '/analytics' do
  varWash(params)

  @customer_id = params[:customer_id]
  @hashfile_id = params[:hashfile_id]
  @button_select_customers = Customers.all

  if params[:customer_id] && !params[:customer_id].empty?
    @button_select_hashfiles = Hashfiles.all(customer_id: params[:customer_id])
  end

  if params[:customer_id] && !params[:customer_id].empty?
    @customers = Customers.first(id: params[:customer_id])
  else
    @customers = Customers.all
  end

  if params[:customer_id] && !params[:customer_id].empty?
    if params[:hashfile_id] && !params[:hashfile_id].empty?
      @hashfiles = Hashfiles.first(id: params[:hashfile_id])
    else
      @hashfiles = Hashfiles.all
    end
  end

  # get results of specific customer if customer_id is defined
  # if we have a customer
  if params[:customer_id] && !params[:customer_id].empty?
    # if we have a hashfile
    if params[:hashfile_id] && !params[:hashfile_id].empty?
      # Used for Total Hashes Cracked doughnut: Customer: Hashfile
      @cracked_pw_count = repository(:default).adapter.select('SELECT COUNT(h.originalhash) FROM hashes h LEFT JOIN hashfilehashes a ON h.id = a.hash_id WHERE (a.hashfile_id = ? AND h.cracked = 1)', params[:hashfile_id])[0].to_s
      @uncracked_pw_count = repository(:default).adapter.select('SELECT COUNT(h.originalhash) FROM hashes h LEFT JOIN hashfilehashes a ON h.id = a.hash_id WHERE (a.hashfile_id = ? AND h.cracked = 0)', params[:hashfile_id])[0].to_s

      # Used for Total Accounts table: Customer: Hashfile
      @total_accounts = @uncracked_pw_count.to_i + @cracked_pw_count.to_i

      # Used for Total Unique Users and originalhashes Table: Customer: Hashfile
      @total_users_originalhash = repository(:default).adapter.select('SELECT a.username, h.originalhash FROM hashes h LEFT JOIN hashfilehashes a ON h.id = a.hash_id LEFT JOIN hashfiles f on a.hashfile_id = f.id WHERE (f.customer_id = ? AND f.id = ?)', params[:customer_id],params[:hashfile_id])

      @total_unique_users_count = repository(:default).adapter.select('SELECT COUNT(DISTINCT(username)) FROM hashfilehashes WHERE hashfile_id = ?', params[:hashfile_id])[0].to_s
      @total_unique_originalhash_count = repository(:default).adapter.select('SELECT COUNT(DISTINCT(h.originalhash)) FROM hashes h LEFT JOIN hashfilehashes a ON h.id = a.hash_id WHERE a.hashfile_id = ?', params[:hashfile_id])[0].to_s

      # Used for Total Run Time: Customer: Hashfile
      @total_run_time = Hashfiles.first(fields: [:total_run_time], id: params[:hashfile_id]).total_run_time

      # make list of unique hashes
      unique_hashes = Set.new
      @total_users_originalhash.each do |entry|
        unique_hashes.add(entry.originalhash)
      end

      hashes = []
      # create array of all hashes to count dups
      @total_users_originalhash.each do |uh|
        unless uh.originalhash.nil?
          hashes << uh.originalhash unless uh.originalhash.empty?
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
      @duphashes = Hash[@duphashes.sort_by { |_k, v| -v }[0..20]]

      users_same_password = []
      @password_users = {}
      # for each unique password hash find the users and their plaintext
      @duphashes.each do |hash|
        dups = repository(:default).adapter.select('SELECT a.username, h.plaintext, h.cracked FROM hashes h LEFT JOIN hashfilehashes a on h.id = a.hash_id LEFT JOIN hashfiles f on a.hashfile_id = f.id WHERE (f.customer_id = ? AND f.id = ? AND h.originalhash = ?)', params[:customer_id], params[:hashfile_id], hash[0] )
        # for each user with the same password hash add user to array
        dups.each do |d|
          if !d.username.nil?
            users_same_password << d.username
          else
            users_same_password << 'NULL'
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
      @cracked_pw_count = repository(:default).adapter.select('SELECT count(h.plaintext) FROM hashes h LEFT JOIN hashfilehashes a on h.id = a.hash_id LEFT JOIN hashfiles f on a.hashfile_id = f.id WHERE (f.customer_id = ? AND h.cracked = 1)', params[:customer_id])[0].to_s
      @uncracked_pw_count = repository(:default).adapter.select('SELECT count(h.originalhash) FROM hashes h LEFT JOIN hashfilehashes a on h.id = a.hash_id LEFT JOIN hashfiles f on a.hashfile_id = f.id WHERE (f.customer_id = ? AND h.cracked = 0)', params[:customer_id])[0].to_s

      # Used for Total Accounts Table: Customer
      @total_accounts = @uncracked_pw_count.to_i + @cracked_pw_count.to_i

      # Used for Total Unique Users and original hashes Table: Customer
      @total_unique_users_count = repository(:default).adapter.select('SELECT COUNT(DISTINCT(username)) FROM hashfilehashes a LEFT JOIN hashfiles f ON a.hashfile_id = f.id WHERE f.customer_id = ?', params[:customer_id])[0].to_s
      @total_unique_originalhash_count = repository(:default).adapter.select('SELECT COUNT(DISTINCT(h.originalhash)) FROM hashes h LEFT JOIN hashfilehashes a ON h.id = a.hash_id LEFT JOIN hashfiles f ON a.hashfile_id = f.id WHERE f.customer_id = ?', params[:customer_id])[0].to_s

      # Used for Total Run Time: Customer:
      @total_run_time = Hashfiles.sum(:total_run_time, conditions: { :customer_id => params[:customer_id] })
    end
  else
    # Used for Total Hash Cracked Doughnut: Total
    @cracked_pw_count = Hashes.count(cracked: 1)
    @uncracked_pw_count = Hashes.count(cracked: 0)

    # Used for Total Accounts Table: Total
    @total_accounts = Hashfilehashes.count

    # Used for Total Unique Users and originalhashes Tables: Total
    @total_unique_users_count = repository(:default).adapter.select('SELECT COUNT(DISTINCT(username)) FROM hashfilehashes')[0].to_s
    @total_unique_originalhash_count = repository(:default).adapter.select('SELECT COUNT(DISTINCT(originalhash)) FROM hashes')[0].to_s

    # Used for Total Run Time:
    @total_run_time = Hashfiles.sum(:total_run_time)
  end

  @passwords = @cracked_results.to_json

  haml :analytics
end

# callback for d3 graph displaying passwords by length
get '/analytics/graph1' do
  varWash(params)

  @counts = []
  @passwords = {}

  if params[:customer_id] && !params[:customer_id].empty?
    if params[:hashfile_id] && !params[:hashfile_id].empty?
      @cracked_results = repository(:default).adapter.select('SELECT h.plaintext FROM hashes h LEFT JOIN hashfilehashes a ON h.id = a.hash_id WHERE h.cracked = 1 AND a.hashfile_id = ?', params[:hashfile_id])
    else
      @cracked_results = repository(:default).adapter.select('SELECT h.plaintext FROM hashes h LEFT JOIN hashfilehashes a ON h.id = a.hash_id LEFT JOIN hashfiles f on a.hashfile_id = f.id WHERE h.cracked = 1 AND f.customer_id = ?', params[:customer_id])
    end
  else
    @cracked_results = repository(:default).adapter.select('SELECT plaintext FROM hashes WHERE cracked = 1')
  end

  @cracked_results.each do |crack|
    unless crack.nil?
      unless crack.length == 0
        len = crack.length
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
    @counts << { length: key, count: value }
  end

  return @counts.to_json
end

# callback for d3 graph displaying top 10 passwords
get '/analytics/graph2' do
  varWash(params)

  plaintext = []
  if params[:customer_id] && !params[:customer_id].empty?
    if params[:hashfile_id] && !params[:hashfile_id].empty?
      @cracked_results = repository(:default).adapter.select('SELECT h.plaintext FROM hashes h LEFT JOIN hashfilehashes a ON h.id = a.hash_id WHERE h.cracked = 1 AND a.hashfile_id = ?', params[:hashfile_id])
    else
      @cracked_results = repository(:default).adapter.select('SELECT h.plaintext FROM hashes h LEFT JOIN hashfilehashes a ON h.id = a.hash_id LEFT JOIN hashfiles f on a.hashfile_id = f.id WHERE h.cracked = 1 AND f.customer_id = ?', params[:customer_id])
    end
  else
    @cracked_results = repository(:default).adapter.select('SELECT plaintext FROM hashes WHERE cracked = 1')
  end

  @cracked_results.each do |crack|
    unless crack.nil?
      plaintext << crack unless crack.empty?
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
  @top10passwords = @top10passwords.sort_by { |_key, value| value }.reverse.to_h
  # we only need top 10
  @top10passwords = Hash[@top10passwords.sort_by { |_k, v| -v }[0..9]]
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
  if params[:customer_id] && !params[:customer_id].empty?
    if params[:hashfile_id] && !params[:hashfile_id].empty?
      @cracked_results = repository(:default).adapter.select('SELECT h.plaintext FROM hashes h LEFT JOIN hashfilehashes a ON h.id = a.hash_id WHERE h.cracked = 1 AND a.hashfile_id = ?', params[:hashfile_id])
    else
      @cracked_results = repository(:default).adapter.select('SELECT h.plaintext FROM hashes h LEFT JOIN hashfilehashes a ON h.id = a.hash_id LEFT JOIN hashfiles f on a.hashfile_id = f.id WHERE h.cracked = 1 AND f.customer_id = ?', params[:customer_id])
    end
  else
    @cracked_results = repository(:default).adapter.select('SELECT plaintext FROM hashes WHERE cracked = 1')
  end
  @cracked_results.each do |crack|
    unless crack.nil?
      plaintext << crack unless crack.empty?
    end
  end

  @topbasewords = []
  @top10basewords = {}
  # get top 10 basewords
  plaintext.each do |pass|
    word_just_alpha = pass.gsub(/^[^a-z]*/i, '').gsub(/[^a-z]*$/i, '')
    unless word_just_alpha.nil?
      if @top10basewords[word_just_alpha].nil?
        @top10basewords[word_just_alpha] = 1
      else
        @top10basewords[word_just_alpha] += 1
      end
    end
  end

  # sort and convert to array of json objects for d3
  @top10basewords = @top10basewords.sort_by { |_key, value| value }.reverse.to_h
  # we only need top 10
  @top10basewords = Hash[@top10basewords.sort_by { |_k, v| -v }[0..9]]
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
    flash[:error] = 'Please provide a search term'
    redirect to('/search')
  end

  if params[:search_type].to_s == 'password'
    @results = repository(:default).adapter.select('SELECT a.username, h.plaintext, h.originalhash, h.hashtype, c.name FROM hashes h LEFT JOIN hashfilehashes a on h.id = a.hash_id LEFT JOIN hashfiles f on a.hashfile_id = f.id LEFT JOIN customers c ON f.customer_id = c.id WHERE h.plaintext like ?', params[:value])
  elsif params[:search_type].to_s == 'username'
    @results = repository(:default).adapter.select('SELECT a.username, h.plaintext, h.originalhash, h.hashtype, c.name FROM hashes h LEFT JOIN hashfilehashes a on h.id = a.hash_id LEFT JOIN hashfiles f on a.hashfile_id = f.id LEFT JOIN customers c ON f.customer_id = c.id WHERE a.username like ?', params[:value])
  elsif params[:search_type] == 'hash'
    @results = repository(:default).adapter.select('SELECT a.username, h.plaintext, h.originalhash, h.hashtype, c.name FROM hashes h LEFT JOIN hashfilehashes a on h.id = a.hash_id LEFT JOIN hashfiles f on a.hashfile_id = f.id LEFT JOIN customers c ON f.customer_id = c.id WHERE h.originalhash like ?', params[:value])
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
def buildCrackCmd(job_id, taskid)
  # order of opterations -m hashtype -a attackmode is dictionary? set wordlist, set rules if exist file/hash
  settings = Settings.first
  hcbinpath = settings.hcbinpath
  maxtasktime = settings.maxtasktime
  @task = Tasks.first(id: taskid)
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

  target_file = 'control/hashes/hashfile_' + job_id.to_s + '_' + taskid.to_s + '.txt'

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
