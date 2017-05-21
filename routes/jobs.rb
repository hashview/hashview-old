# encoding: utf-8
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
    if @job.status == 'Running' || @job.status == 'Importing' || @job.status == 'Queued'
      flash[:error] = 'You need to stop the job before deleting it.'
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

  @customers = Customers.all(order: [:name.asc])
  @job = Jobs.first(id: params[:job_id])

  if @job
    if @job.status == 'Running' || @job.status == 'Queued'
      flash[:error] = 'You cannot edit a job that is running or queued'
      redirect to('/jobs/list')
    end
  end

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
    pre_existing_customer = Customers.all(name: params[:name])
    if !pre_existing_customer.empty? || pre_existing_customer.nil?
      flash[:error] = 'Customer ' + params[:name] + ' already exists.'
      redirect to('/jobs/create')
    end
 
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
  params[:edit] == '1' ? job = Jobs.first(id: params[:job_id]) : job = Jobs.new

  job.name = params[:job_name]
  job.last_updated_by = getUsername
  job.customer_id = customer_id

  params[:notify] == 'on' ? job.notify_completed = '1' : job.notify_completed = '0'
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
  @hashfiles.each do |hashfile|
    hashfile_cracked_count = repository(:default).adapter.select('SELECT COUNT(h.originalhash) FROM hashes h LEFT JOIN hashfilehashes a ON h.id = a.hash_id WHERE (a.hashfile_id = ? AND h.cracked = 1)', hashfile.id)[0].to_s 
    hashfile_total_count = repository(:default).adapter.select('SELECT COUNT(h.originalhash) FROM hashes h LEFT JOIN hashfilehashes a ON h.id = a.hash_id WHERE a.hashfile_id = ?', hashfile.id)[0].to_s
    @cracked_status[hashfile.id] = hashfile_cracked_count.to_s + '/' + hashfile_total_count.to_s
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

  url = "/jobs/assign_tasks?job_id=#{params[:job_id]}&customer_id=#{params[:customer_id]}&hashid=#{params[:hash_file]}"
  url = url + '&edit=1' if params[:edit]
  redirect to(url)
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
      flash[:error] = 'You must assign at least one task'
      redirect to("/jobs/assign_tasks?job_id=#{params[:job_id]}&customer_id=#{params[:customer_id]}&hashid=#{params[:hash_file]}")
    end
  end

  # create the job if it doesnt exist yet and make sure its stopped
  job = Jobs.first(id: params[:job_id])
  job.status = 'Stopped'
  job.save

  # grab existing jobtasks if there are any
  @jobtasks = Jobtasks.all(job_id: params[:job_id])
  @tasks = Tasks.all

  # prevent adding duplicate tasks to a job
  #count = Hash.new 0
  #params[:tasks] = params[:task].uniq
  puts params
  if params[:tasks]
    # make sure the task that the user is adding is not already assigned to the job
    if params[:edit]
      params[:tasks].each do |t|
        @jobtasks.each do |jt|
          if jt.task_id == t.to_i
            flash[:error] = "Your job already has a task you are trying to add (task id: #{t})"
            redirect to("/jobs/assign_tasks?job_id=#{params[:job_id]}&customer_id=#{params[:customer_id]}&hashid=#{params[:hash_file]}&edit=1")
          end
        end
      end
    end
    # prevent user from adding multiples of the same task
    if params[:tasks].uniq!
      puts params
      flash[:error] = 'You cannot have duplicate tasks.'
      url = "/jobs/assign_tasks?job_id=#{params[:job_id]}&customer_id=#{params[:customer_id]}&hashid=#{params[:hash_file]}"
      url += '&edit=1' if params[:edit]
      redirect to(url)
    end
  end

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
      # we are using a db queue instead for public api
      queue = Taskqueues.new
      queue.jobtask_id = jt.id
      queue.job_id = @job.id
      queue.command = cmd
      queue.status = 'Queued'
      queue.save
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
    if task.status == 'Queued' || task.status == 'Running'
      task.status = 'Canceled'
      task.save
    end
  end

  # we are using a db queue instead for public api
  # remove all items from queue
  queue = Taskqueues.all(job_id: @job.id)
  queue.destroy if queue

  # TODO I see a problem with this once we have multiple agents. but for now, i'm too drunk to deal with it
  @jobtasks.each do |task|
    if task.status == 'Running'
      redirect to("/jobs/stop/#{task.job_id}/#{task.task_id}")
    end
  end

  redirect to('/jobs/list')
end

get '/jobs/stop/:job_id/:task_id' do
  varWash(params)

  # validate if running
  jt = Jobtasks.first(job_id: params[:job_id], task_id: params[:task_id])
  unless jt.status == 'Running'
    return 'That specific Job and Task is not currently running.'
  end

  # update jobtasks to "canceled"
  jt.status = 'Canceled'
  jt.save

  taskqueue = Taskqueues.all(jobtask_id: jt.id)
  taskqueue.each do |tq|
    tq.status = 'Canceled'
    tq.save
  end

  referer = request.referer.split('/')

  if referer[3] == 'home'
    redirect to('/home')
  elsif referer[3] == 'jobs'
    redirect to('/jobs/list')
  end
end

get '/jobs/local_check' do
  varWash(params)

  # TODO offer the ability to upload to hub

  @jobs = Jobs.first(id: params[:job_id])
  @previously_cracked = repository(:default).adapter.select('SELECT h.originalhash, h.plaintext, h.hashtype, a.username FROM hashes h LEFT JOIN hashfilehashes a ON h.id = a.hash_id WHERE (a.hashfile_id = ? AND h.cracked = 1)', @jobs.hashfile_id)

  @url = '/jobs'
  hub_settings = HubSettings.first
  hub_settings.status == 'registered' ? @url = @url + '/hub_check' : @url = @url + '/assign_tasks'

  @url += "?job_id=#{params[:job_id]}"
  @url += '&edit=1' if params[:edit]

  haml :job_local_check
end

get '/jobs/hub_check' do
  varWash(params)

  @results = []
  results_entry = {
    username: '',
    originalhash: '',
    hub_hash_id: '',
    hashtype: '',
    show_results: '0'
  }

  @jobs = Jobs.first(id: params[:job_id])
  @hashfile_hashes = Hashfilehashes.all(hashfile_id: @jobs.hashfile_id)
  # Each hashfile might have multiple duplicate hashes, we need a unique list
  @hashfile_hashes.each do |entry|
    hash = Hashes.first(id: entry.hash_id, cracked: '0')
    unless hash.nil?
      hub_response = Hub.hashSearch(hash.originalhash)
      hub_response = JSON.parse(hub_response)
      if hub_response['status'] == '200' && hub_response['cracked'] == '1'
        results_entry['username'] = entry.username
        results_entry['originalhash'] = hash.originalhash
        results_entry['hub_hash_id'] = hub_response['hash_id']
        results_entry['hashtype'] = hub_response['hashtype']
        results_entry['show_results'] = '1'
      end
    end
  end
  @results.push(results_entry)

  haml :job_hub_check
end

################################

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

