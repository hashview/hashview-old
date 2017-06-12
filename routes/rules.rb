# encoding: utf-8

get '/rules/list' do
  @rules = Rules.all
  @rule_content = []

  @rules.each do |rule_file|
    element = {}
    element['id'] = rule_file.id
    element['name'] = rule_file.name
    element['size'] = rule_file.size
    text = File.open(rule_file.path).read
    text.gsub!(/\r\n?/, "\n")
    @content = []
    text.each_line do |line|
      line = line.gsub(/\s+/, '')
      @content.push(line)
    end
    element['content'] = @content
    @rule_content.push(element)
  end

  haml :rule_list
end

post '/rules/new' do
  varWash(params)

  if !params[:rules_file_name] || params[:rules_file_name].nil?
    flash[:error] = 'Your Rules file must have a name.'
    redirect to('/rules/list')
  end

  if params[:new_rules].nil? || params[:new_rules].empty?
    flash[:error] = 'You must supply at least one rule.'
    redirect to('/rules/list')
  end

  # Change our name
  name = params[:rules_file_name].gsub('\s', '_')

  # Check to see if we've cont a name conflict
  rules_file_check = Rules.first(name: name)
  unless rules_file_check.nil? || rules_file_check.empty?
    flash[:error] = 'That rules name is in use, please pick a new one.'
    redirect to('/rules/list')
  end

  # Create DB entry first so that our background job doesnt accidentally pull it in.
  rules_file = Rules.new
  rules_file.name = name
  rules_file.lastupdated = Time.now()

  # temporarily save file for testing
  rules_file_path_name = "control/rules/#{name}.rule"
  rules_file.path = rules_file_path_name
  rules_file.size = 0 # note this will get updated by background task
  rules_file.save

  # Parse uploaded file into an array
  rules_array = params[:new_rules].to_s.gsub(/\x0d\x0a/, "\x0a") # in theory we shouldnt run into any false positives?
  File.open(rules_file_path_name, 'w') { |f| f.puts(rules_array) }

  results = Rules.first(name: name)
  Resque.enqueue(FileChecksum('rules', results.id))

  flash[:success] = 'Successfully created new rule.'
  redirect to('/rules/list')
end

get '/rules/delete/:id' do
  varWash(params)

  rules_file = Rules.first(id: params[:id])
  if !rules_file
    flash[:error] = 'no such rules file exists.'
    redirect to('/rules/list')
  else
    # check if rule file is in use
    # TODO tasks should store rules by id not name
    @task_list = Tasks.all(hc_rule: rules_file.name)
    unless @task_list.empty?
      flash[:error] = 'This Rules file is associated with a task, it cannot be deleted.'
      redirect to('/rules/list')
    end

    # remove from filesystem
    File.delete(rules_file.path)

    # delete from db
    rules_file.destroy

  end
  flash[:success] = 'Rules file deleted.'
  redirect to('/rules/list')
end

post '/rules/save/:id' do
  # varWash(params)

  if !params[:edit_rules] || params[:edit_rules].nil?
    flash[:error] = 'You must have some rules.'
    redirect to('/rules/list')
  end

  if !params[:id] || params[:id].nil?
    flash[:error] = 'Rule file must be specified'
    redirect to('/rules/list')
  end

  # TODO do we want to lock rule files from being edited when they're in an existing job?

  @rules = params[:edit_rules].split(/[\r\n]+/)

  # move old rule to tmp folder
  rules_file = Rules.first(id: params[:id])
  cmd = "mv #{rules_file.path} control/tmp/#{rules_file.name}"
  `#{cmd}`

  # write to disk
  File.open(rules_file.path, 'w') { |f| f.puts(@rules) }

  # update file size
  size = File.foreach(rules_file.path).inject(0) { |c| c + 1}
  rules_file.size = size
  rules_file.save

  Resque.enqueue(FileChecksum('rules', params[:id]))

  flash[:success] = 'Successfully uploaded rules file.'
  redirect to('/rules/list')
end