get '/task_groups/list' do
  @task_groups = TaskGroups.all
  @wordlists = Wordlists.all
  @rules = Rules.all
  @jobtasks = Jobtasks.all
  @jobs = Jobs.all

  haml :task_group_list
end

get '/task_groups/delete/:id' do
  varWash(params)

  @job_tasks = Jobtasks.where(task_id: params[:id]).all
  unless @job_tasks.empty?
    flash[:error] = 'That task is currently used in a job.'
    redirect to('/tasks/list')
  end

  @task = Tasks.first(id: params[:id])
  @task.destroy if @task

  redirect to('/tasks/list')
end

get '/task_groups/edit/:id' do
  varWash(params)

  @task = Tasks.first(id: params[:id])
  @wordlists = Wordlists.all
  @hc_settings = HashcatSettings.first

  if @task.hc_attackmode == 'combinator'
    @combinator_wordlists = @task.wl_id.split(',')
    if @task.hc_rule =~ /--rule-left=(.*) --rule-right=(.*)/
      @combinator_left_rule = Regexp.last_match(1)
      @combinator_right_rule = Regexp.last_match(2)
    elsif @task.hc_rule =~ /--rule-left=(.*)/
      @combinator_left_rule = Regexp.last_match(1)
    elsif @task.hc_rule =~ /--rule-right=(.*)/
      @combinator_right_rule = Regexp.last_match(1)
    end
  end

  @rules = Rules.all

  haml :task_edit
end

post '/task_groups/edit/:id' do
  varWash(params)

  if !params[:name] || params[:name].nil?
    flash[:error] = 'The task requires a name.'
    redirect to("/tasks/edit/#{params[:id]}")
  end

  wordlist = Wordlists.first(id: params[:wordlist])

  # must have two word lists
  if params[:attackmode] == 'combinator'
    wordlist_count = 0
    wordlist_list = ''
    rule_list = ''
    @wordlists = Wordlists.all
    @wordlists.each do |wordlist_check|
      params.keys.each do |key|
        next unless params[key] == 'on' && key == "combinator_wordlist_#{wordlist_check.id}"
        if wordlist_list == ''
          wordlist_list = wordlist_check.id.to_s + ','
        else
          wordlist_list += wordlist_check.id.to_s
        end
        wordlist_count += 1
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
    task.hc_rule = params[:rule].to_i
    task.hc_rule = 'none' if params[:rule].to_i.zero?
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
    p 'task group task ids type: ' + @task_group_task_ids.class.to_s
    p 'task group task id: ' + @task_group_task_ids.to_s
    @task_group_task_ids.each do |id|
      p 'id type: ' + id.class.to_s
      element = {}
      p 'task id: ' + id.to_s
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
    next if @task_group_task_ids.include? task.id.to_s
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
