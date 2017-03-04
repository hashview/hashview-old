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

  @customers = Customers.all(order: [:name.asc])
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
  @hashfiles.each do |hashfile|
    hashfile_cracked_count = repository(:default).adapter.select('SELECT COUNT(h.originalhash) FROM hashes h LEFT JOIN hashfilehashes a ON h.id = a.hash_id WHERE (a.hashfile_id = ? AND h.cracked = 1)', hashfile.id)[0].to_s 
    hashfile_total_count = repository(:default).adapter.select('SELECT COUNT(h.originalhash) FROM hashes h LEFT JOIN hashfilehashes a ON h.id = a.hash_id WHERE a.hashfile_id = ?', hashfile.id)[0].to_s
    @cracked_status[hashfile.id] = hashfile_cracked_count.to_s + "/" + hashfile_total_count.to_s
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
      if params[:edit]
        redirect to("/jobs/assign_tasks?job_id=#{params[:job_id]}&customer_id=#{params[:customer_id]}&hashid=#{params[:hash_file]}&edit=1")
      else
        redirect to("/jobs/assign_tasks?job_id=#{params[:job_id]}&customer_id=#{params[:customer_id]}&hashid=#{params[:hash_file]}")
      end
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
    if task.status == 'Queued'
      task.status = 'Canceled'
      task.save
      cmd = buildCrackCmd(@job.id, task.task_id)
      cmd = cmd + ' | tee -a control/outfiles/hcoutput_' + @job.id.to_s + '.txt'
      puts 'STOP CMD: ' + cmd
      # we are using a db queue instead for public api
      queue = Taskqueues.first(job_id: @job_id)
      queue.destroy if queue
    end
  end
  
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
  # find pid
  pid = `ps -ef | grep hashcat | grep hc_cracked_#{params[:job_id]}_#{params[:task_id]}.txt | grep -v 'ps -ef' | grep -v 'sh \-c' | awk '{print $2}'`
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

