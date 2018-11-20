# encoding: utf-8
get '/jobs/list' do
  @targets_cracked = {}
  @customer_names = {}
  @wordlist_id_to_name = {}

  @jobs = Jobs.order(Sequel.desc(:id))
  @tasks = Tasks.all
  @jobtasks = Jobtasks.all
  @wordlists = Wordlists.all
  @hashfiles = Hashfiles.all
  @rules = Rules.all

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
    @jobtasks = Jobtasks.where(job_id: params[:id]).all
    @jobtasks.each do |jobtask|
      jobtask.destroy unless jobtask.nil?
    end
    @job.destroy
  end

  redirect to('/jobs/list')
end

get '/jobs/create' do
  varWash(params)

  @customers = Customers.order(Sequel.asc(:name)).all
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
    pre_existing_customer = Customers.where(name: params[:name]).all
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
  job.owner = getUsername
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

  @hashfiles = Hashfiles.where(customer_id: params[:customer_id]).all
  @customer = Customers.first(id: params[:customer_id])

  @cracked_status = {}
  @hashfiles.each do |hashfile|
    hashfile_cracked_count = HVDB.fetch('SELECT COUNT(h.originalhash) as count FROM hashes h LEFT JOIN hashfilehashes a ON h.id = a.hash_id WHERE (a.hashfile_id = ? AND h.cracked = 1)', hashfile.id)[:count]
    hashfile_cracked_count = hashfile_cracked_count[:count]
    hashfile_total_count = HVDB.fetch('SELECT COUNT(h.originalhash) as count FROM hashes h LEFT JOIN hashfilehashes a ON h.id = a.hash_id WHERE a.hashfile_id = ?', hashfile.id)[:count]
    hashfile_total_count = hashfile_total_count[:count]
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
  url += '&edit=1' if params[:edit]
  redirect to(url)
end

get '/jobs/assign_tasks' do
  varWash(params)

  @job = Jobs.first(id: params[:job_id])
  @jobtasks = Jobtasks.where(job_id: params[:job_id]).all
  @task_groups = TaskGroups.all
  @wordlists = Wordlists.all
  @hc_settings = HashcatSettings.first
  @rules = Rules.all
  @tasks = Tasks.all
  @available_tasks = []
  # Im sure there's a better way to do this
  @tasks.each do |task|
    element = {}
    inuse = Jobtasks.where(job_id: params[:job_id], task_id: task.id).first
    next unless inuse.nil?
    element['id'] = task.id
    element['name'] = task.name
    @available_tasks.push(element)
  end

  # Create jobtasks_task object
  # not a fan of this approach, but not sure if there's a better way
  @jobtasks_tasks = []
  @jobtasks.each do |jobtask_entry|
    element = {}
    element['jobtask_id'] = jobtask_entry.id
    element['task_id'] = jobtask_entry.task_id
    task = Tasks.first(id: jobtask_entry.task_id)
    element['task_name'] = task.name
    element['task_type'] = task.hc_attackmode
    @jobtasks_tasks.push(element)
  end

  haml :assign_tasks
end

get '/jobs/move_task' do
  varWash(params)

  # We create an array of all related jobtasks, remove existing jobtasks, re-arrange, and create new jobtasks (this way we dont have to worry about non-contigous jobtasks ids)
  @jobtasks = Jobtasks.where(job_id: params[:job_id]).all

  @temp_jobtasks = []
  @new_jobtasks = []
  @jobtasks.each do |entry|
    @temp_jobtasks << entry.task_id
  end

  if params[:action] == 'UP'
    if @temp_jobtasks[0] == params[:task_id].to_i
      flash[:error] = 'Task is already at the top.'
      redirect to("/jobs/assign_tasks?job_id=#{params[:job_id]}")
    end

    @temp_jobtasks.each_with_index do |task_id, index|
      if @temp_jobtasks[index + 1] == params[:task_id].to_i
        @new_jobtasks << params[:task_id].to_i
        @new_jobtasks << @temp_jobtasks[index]
        @temp_jobtasks.delete_at(index)
      else
        @new_jobtasks << @temp_jobtasks[index].to_i
      end
    end

  elsif params[:action] == 'DOWN'
    if @temp_jobtasks[-1] == params[:task_id].to_i
      flash[:error] = 'Task is already at the bottom.'
      redirect to("/jobs/assign_tasks?job_id=#{params[:job_id]}")
    end

    @temp_jobtasks.each_with_index do |task_id, index|
      if @temp_jobtasks[index] == params[:task_id].to_i
        @new_jobtasks << @temp_jobtasks[index + 1]
        @new_jobtasks << params[:task_id].to_i
        @temp_jobtasks.delete_at(index + 1)
      else
        @new_jobtasks << @temp_jobtasks[index].to_i
      end
    end
  end

  @jobtasks = HVDB[:jobtasks]
  @jobtasks.filter(job_id: params[:job_id]).delete

  @new_jobtasks.each do |new_jobtask_entry|
    job_task = Jobtasks.new
    job_task.job_id = params[:job_id]
    job_task.task_id = new_jobtask_entry.to_i
    job_task.save
  end

  redirect to("/jobs/assign_tasks?job_id=#{params[:job_id]}")
end

get '/jobs/remove_task' do
  varWash(params)
  jobtask = Jobtasks.first(id: params[:jobtask_id])
  jobtask.destroy unless jobtask.nil?

  redirect to("/jobs/assign_tasks?job_id=#{params[:job_id]}")
end

get '/jobs/assign_task' do
  varWash(params)

  # Check if task already exists
  existing_jobtask = Jobtasks.first(job_id: params[:job_id], task_id: params[:task_id])
  unless existing_jobtask.nil?
    flash[:error] = 'Task is already assigned to the job. You can not run the same task twice.'
    redirect to("/jobs/assign_tasks?job_id=#{params[:job_id]}")
  end

  # Append task to job
  job_task = Jobtasks.new
  job_task.job_id = params[:job_id]
  job_task.task_id = params[:task_id]
  job_task.save

  # return to assign_tasks
  redirect to("/jobs/assign_tasks?job_id=#{params[:job_id]}")
end

get '/jobs/assign_task_group' do
  varWash(params)

  task_group = TaskGroups.first(id: params[:task_group_id])
  unless task_group.nil?
    @task_group_ids = task_group.tasks.scan(/\d+/)
    @task_group_ids.each do |task_id|
      existing_jobtask = Jobtasks.first(job_id: params[:job_id], task_id: task_id)
      next unless existing_jobtask.nil?
      # Append task to job
      job_task = Jobtasks.new
      job_task.job_id = params[:job_id]
      job_task.task_id = task_id
      job_task.save
    end
  end

  # return to assign_tasks
  redirect to("/jobs/assign_tasks?job_id=#{params[:job_id]}")
end

get '/jobs/complete' do
  varWash(params)

  jobtasks = Jobtasks.where(job_id: params[:job_id]).all

  if jobtasks.empty?
    flash[:error] = 'You must assign at least one task.'
    redirect to '/jobs/assign_tasks?job_id=' + params[:job_id].to_s
  end

  jobtasks.each do |task|
    task.status = 'Ready'
    task.save
  end

  job = Jobs.first(id: params[:job_id])
  job.status = 'Ready'
  job.save

  params[:edit].to_s == '1' ? flash[:success] = 'Job updated.' : flash[:success] = 'Job created.'
  redirect to('/jobs/list')
end

get '/jobs/start/:id' do
  varWash(params)

  job = Jobs.first(id: params[:id])
  hashfile = Hashfiles.find(id: job.hashfile_id)
  hashfile_hash = Hashfilehashes.find(hashfile_id: hashfile.id) if hashfile

  unless job
    flash[:error] = 'No such job exists.'
    redirect to('/jobs/list')
  end

  if hashfile.nil? || hashfile_hash.nil?
    flash[:error] = 'You have an error in your hashfile'
    redirect to('/jobs/list')
  end

  @jobtasks = Jobtasks.where(job_id: params[:id]).all
  unless @jobtasks
    flash[:error] = 'This job has no tasks to run.'
    return 'This job has no tasks to run.'
  end

  @jobtasks.each do |job_task|

    # do not start tasks if they have already been completed.
    # set all other tasks to status of queued

    next unless job_task.status != 'Completed'
    # toggle the job status to run
    # We shouldn't need to do this for every task, just once
    job.status = 'Queued'
    job.queued_at = DateTime.now
    job.save

    # set jobtask status to queued
    job_task.status = 'Queued'
    job_task.command = buildCrackCmd(job.id, job_task.task_id)
    job_task.keyspace_pos = 0
    job_task.save
  end

  if job.status == 'Completed'
    flash[:error] = 'All tasks for this job have been completed. To prevent overwriting your results, you will need to create a new job with the same tasks in order to rerun the job.'
    redirect to('/jobs/list')
  end

  redirect to('/home')
end

get '/jobs/stop/:id' do
  varWash(params)

  @job = Jobs.first(id: params[:id])
  @jobtasks = Jobtasks.where(job_id: params[:id]).all

  @job.status = 'Canceled'
  @job.ended_at = Time.now
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
  queue = Taskqueues.where(job_id: @job.id).all
  queue.each do |q|
      q.destroy unless q.nil?
    end

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

  taskqueue = Taskqueues.where(jobtask_id: jt.id).all
  taskqueue.each do |tq|
    tq.status = 'Canceled'
    tq.save
  end

  # If there are no more jobtasks, set job status to canceled
  @job_tasks = Jobtasks.where(job_id: params[:job_id], status: 'Running').or(job_id: params[:job_id], status: 'Queued').all
  if @job_tasks.empty?
    job = Jobs.first(id: params[:job_id])
    job.status = 'Canceled'
    job.save
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
  @previously_cracked = HVDB.fetch('SELECT h.originalhash, h.plaintext, h.hashtype, a.username FROM hashes h LEFT JOIN hashfilehashes a ON h.id = a.hash_id WHERE (a.hashfile_id =? AND h.cracked = 1)', @jobs.hashfile_id)
  @url = '/jobs'

  # Check to see if we're going to use the hub
  hub_settings = HubSettings.first
  hub_settings.status == 'registered' ? @url += '/hub_permission_check' : @url += '/assign_tasks'

  @url += "?job_id=#{params[:job_id]}"
  @url += '&edit=1' if params[:edit]

  haml :job_local_check
end

get '/jobs/hub_permission_check' do
  varWash(params)
  @jobs = Jobs.first(id: params[:job_id])

  haml :job_hub_permission_check
end

get '/jobs/hub_check' do
  varWash(params)

  @jobs = Jobs.first(id: params[:job_id])
  @hashfile_hashes = Hashfilehashes.first(hashfile_id: @jobs.hashfile_id)
  @hashes = Hashes.first(id: @hashfile_hashes.hash_id)

  # Check to see if the hash type is even supported
  hub_response = Hub.getSupportedHashtypes
  hub_response = JSON.parse(hub_response)
  if hub_response['status'] == '200'
    @hub_supported_hashtypes = hub_response['hashtypes']
    unless @hub_supported_hashtypes.include? @hashes.hashtype.to_s
      p 'UNSUPPORTED HASHTYPE: ' + @hub_supported_hashtypes.to_s + ' vs ' + @hashes.hashtype.to_s
      flash[:error] = 'Sorry. The hub does not support that hashtype.'
      redirect to("jobs/assign_tasks?job_id=#{params[:job_id]}")
    end
  end

  # Looks like our hashes are supported by the hub
  @results = []
  results_entry = {
    username: '',
    originalhash: '',
    hub_hash_id: '',
    hashtype: '',
    show_results: '0'
  }

  @hashfile_hashes = Hashfilehashes.where(hashfile_id: @jobs.hashfile_id).all
  # Each hashfile might have multiple duplicate hashes, we need a unique list
  @hash_array = []
  @hashfile_hashes.each do |entry|
    hash = Hashes.first(id: entry.hash_id, cracked: '0')
    next if hash.nil?
    element = {}
    element['ciphertext'] = hash.originalhash
    element['hashtype'] = hash.hashtype.to_s
    @hash_array.push(element)
  end

  hub_response = Hub.hashSearch(@hash_array)
  hub_response = JSON.parse(hub_response)
  if hub_response['status'] == '200'
    @hub_hash_results = hub_response['hashes']
    @hub_hash_results.each do |element|
      next unless element['cracked'] == '1'
      hash = Hashes.first(originalhash: element['ciphertext'])
      results_entry['id'] = hash.id
      # TODO
      # Adding usernames to this result would be great
      results_entry['ciphertext'] = element['ciphertext']
      results_entry['hub_hash_id'] = element['hash_id']
      results_entry['hashtype'] = element['hashtype']
      results_entry['show_results'] = '1'
      @results.push(results_entry)
      results_entry = {}
    end
  end

  if @results.empty?
    flash[:error] = 'No Hub results found.'
    redirect to("/jobs/assign_tasks?job_id=#{params[:job_id]}")
  end

  haml :job_hub_check
end

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
