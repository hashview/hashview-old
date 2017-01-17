# encoding: utf-8
class HashView < Sinatra::Application
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
end
