get '/task_groups/list' do
  @task_groups = TaskGroups.all
  @tasks = Tasks.all

  haml :task_group_list
end

get '/task_groups/delete/:id' do
  varWash(params)

  task_group = TaskGroups.first(id: params[:id])
  task_group.destroy if task_group

  redirect to('/task_groups/list')
end

get '/task_groups/create' do
  varWash(params)

  @tasks = Tasks.all

  haml :task_group_edit
end

post '/task_groups/create' do
  varWash(params)

  if !params[:name] || params[:name].empty?
    flash[:error] = 'You must provide a name for your task group!'
    redirect to('/task_groups/create')
  end

  @task_groups = TaskGroups.where(name: params[:name]).all
  unless @task_groups.nil?
    @task_groups.each do |entry|
      if entry.name == params[:name]
        flash[:error] = 'Name already in use, pick another'
        redirect to('/task_groups/create')
      end
    end
  end

  task_group = TaskGroups.new
  task_group.name = params[:name]
  task_group.save

  redirect to('/task_groups/assign_tasks?id=' + task_group.id.to_s)
end

get '/task_groups/assign_tasks' do
  varWash(params)

  @task_group = TaskGroups.first(id: params[:id])
  @task_group_tasks = []
  unless @task_group.tasks.nil?

    @task_group_task_ids = @task_group.tasks.scan(/\d/)
    @task_group_task_ids.each do |id|
      element = {}
      task = Tasks.first(id: id)
      next unless task
      element['task_id'] = task.id
      element['task_name'] = task.name
      element['task_type'] = task.hc_attackmode
      @task_group_tasks.push(element)
    end
  end

  @wordlists = Wordlists.all
  @hc_settings = HashcatSettings.first
  @rules = Rules.all
  @tasks = Tasks.all
  @available_tasks = []
  # Im sure there's a better way to do this
  @tasks.each do |task|
    element = {}
    next if @task_group_task_ids && (@task_group_task_ids.include? task.id.to_s)
    element['id'] = task.id
    element['name'] = task.name
    @available_tasks.push(element)
  end

  haml :task_group_assign_tasks
end

get '/task_groups/move_task' do
  varWash(params)

  # We create an array of all related task group tasks, re-arrange, and assign.
  task_group = TaskGroups.first(id: params[:id])
  @new_task_ids = []
  unless task_group.tasks.nil?
    @task_group_task_ids = task_group.tasks.scan(/\d/)
    if params[:action] == 'UP'
      if @task_group_task_ids[0] == params[:task_id]
        flash[:error] = 'Task is already at the top.'
        redirect to("/task_groups/assign_tasks?id=#{params[:id]}")
      end

      @task_group_task_ids.each_with_index do |_unused, index|
        if @task_group_task_ids[index+1] == params[:task_id]
          @new_task_ids.push(params[:task_id])
          @new_task_ids.push(@task_group_task_ids[index])
          @task_group_task_ids.delete_at(index)
        else
          @new_task_ids.push(@task_group_task_ids[index])
        end
      end
    elsif params[:action] == 'DOWN'
      if @task_group_task_ids[-1] == params[:task_id]
        flash[:error] = 'Task is already at the bottom.'
        redirect to("/task_groups/assign_tasks?id=#{params[:id]}")
      end

      @task_group_task_ids.each_with_index do |_unused, index|
        if @task_group_task_ids[index] == params[:task_id]
          @new_task_ids.push(@task_group_task_ids[index])
          @new_task_ids.push(params[:task_id])
          @task_group_task_ids.delete_at(index + 1)
        else
          @new_task_ids.push(@task_group_task_ids[index])
        end
      end
    end
  end

  task_group.tasks = @new_task_ids.to_s
  task_group.save

  redirect to("/task_groups/assign_tasks?id=#{params[:id]}")
end

get '/task_groups/remove_task' do
  varWash(params)

  task_group = TaskGroups.first(id: params[:id])
  unless task_group.tasks.nil?
    @task_group_ids = task_group.tasks.scan(/\d/)
    @remaining_task_ids = []
    @task_group_ids.each do |task|
      next if task.to_i == params['task_id'].to_i
      @remaining_task_ids.push(task)
    end
  end

  task_group.tasks = @remaining_task_ids.to_s
  task_group.save

  redirect to("/task_groups/assign_tasks?id=#{params[:id]}")
end

get '/task_groups/assign_task' do
  varWash(params)

  # Check if task is already assigned
  task_group = TaskGroups.first(id: params[:id])

  if task_group.tasks.nil?
    task_group.tasks = Array(params['task_id']).to_s
  else
    @task_group_ids = task_group.tasks.scan(/\d/)
    if @task_group_ids.include? params['task_id']
      flash[:error] = 'Task is already assigned to the group.'
      redirect to("/tasks_groups/assign_tasks?id=#{params[:id]}")
    end
    @task_group_ids.push(params['task_id'])
    task_group.tasks = @task_group_ids.to_s
  end

  task_group.save
  # return to assign_tasks
  redirect to("/task_groups/assign_tasks?id=#{params[:id]}")
end
