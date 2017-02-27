# my shameful attempt at implementing a REST API

# our main worker queue
get '/v1/queue' do
  @queue = Taskqueues.first(status: "Queued")
  if @queue
    return @queue.to_json
  else
    status 200
    {
        status: 200,
        type: 'Error',
        message: 'There are no items on the queue to process'
    }.to_json
  end
end

# remove item from queue
get '/v1/queue/:id/remove' do
  @queue = Taskqueues.first(id: params[:id])
  @queue.destroy
  return
end

# update status of taskqueue item
post '/v1/queue/:taskqueue_id/status' do
  jdata = JSON.parse(request.body.read)
  agent = Agents.first(uuid: jdata['agent_uuid'])
  puts "[+] updating taskqueue id: #{params['taskqueue_id']} to status: #{jdata['status']}"
  updateTaskqueueStatus(params['taskqueue_id'], jdata['status'], agent.id)
end

# update status of job
post '/v1/jobtask/:jobtask_id/status' do
  jdata = JSON.parse(request.body.read)
  puts jdata
  puts "[+] updating jobtask id: #{params['jobtask_id']} to status: #{jdata['status']}"
  updateJobStatus(jdata['job_id'], jdata['status'])
end

# return jobtask details
get '/v1/jobtask/:id' do
  jobtask = Jobtasks.first(id: params[:id])
  return jobtask.to_json
end

# provide job info
get '/v1/job/:id' do
  @job = Jobs.first(id: params[:id])
  return @job.to_json
end

# provide wordlist info
get '/v1/wordlist' do
  wordlists = Wordlists.all
  data = {}
  data['wordlists'] = wordlists
  return data.to_json
end

# serve a wordlist
get '/v1/wordlist/:id' do
  wordlist = Wordlists.first(id: params[:id])
  send_file wordlist.path, :type => 'text', :filename => wordlist.path.split('/')[-1]
end


# generate and serve hashfile
# TODO: make this a background worker in resque
get '/v1/jobtask/:jobtask_id/hashfile/:hashfile_id' do
  puts '===== creating hash_file ======='
  jobtask_id = params[:jobtask_id]
  hashfile_id = params[:hashfile_id]

  # we need jobtask info to make hashfile path
  jobtasks = Jobtasks.first(id: jobtask_id)
  #job = jobs.first(id: jobtasks.job_id)

  @hash_ids = Set.new
  Hashfilehashes.all(fields: [:hash_id], hashfile_id: hashfile_id).each do |entry|
    @hash_ids.add(entry.hash_id)
  end
  targets = Hashes.all(fields: [:originalhash], id: @hash_ids, cracked: 0)

  hash_file = 'control/hashes/hashfile_' + jobtasks.job_id.to_s + '_' + jobtasks.task_id.to_s + '.txt'
  hashtype_target = Hashes.first(id: @hash_ids)
  hashtype = hashtype_target.hashtype.to_s

  # if requester is local agent, write directly to disk, otherwise serve as download
  File.open(hash_file, 'w') do |f|
    targets.each do |entry|
      if hashtype == '5500'
        # Hashtype is NetNTLMv1
        f.puts ':::' + entry.originalhash # we dont need to include the username for this
      else
        f.puts entry.originalhash
      end
    end
    f.close
  end

  puts '===== Hash_File Created ======'

  send_file hash_file

end

# accept uploaded crack files
post '/v1/jobtask/:jobtask_id/crackfile/upload' do
  tmpfile = "control/tmp/#{rand.to_s[2..2048]}.txt"
  puts "[+] Agent uploaded crack file. Saving to: #{tmpfile}"
  File.open(tmpfile, 'wb') do |f|
    f.write(params[:file][:tempfile].read)
  end
  importCracked(params[:jobtask_id], tmpfile)
  return 'upload successful'
end

# accept upload hashcat status
# TODO complete this
post '/v1/hcoutput/status' do
  puts "parsing uploaded hcoutput hash"
  return request.body.read
end

# heartbeat
get '/v1/agents/:uuid/heartbeat' do
  response = Hash.new
  if params[:uuid].nil?
    status 200
    {
        Status: 200,
        Type: 'Error',
        Message: 'Missing UUID'
    }.to_json
  else
    @agent = Agents.first(:uuid => params[:uuid])
    if !@agent.nil?
      if @agent.status == "Authorized"
        redirect to("/v1/agents/#{params[:uuid]}/authorize")
      else
        @agent.status = "Online"
        @agent.heartbeat = Time.now
        @agent.save
        {
          Status: 200,
          Type: 'Message',
          Message: 'OK'
        }.to_json
      end
    else
      newagent = Agents.new
      newagent.uuid = params[:uuid]
      newagent.name = params[:uuid] + " (untrusted)"
      newagent.status = "Pending"
      newagent.src_ip = "#{request.ip}"
      newagent.heartbeat = Time.now
      newagent.save
      response['Message'] = 'Go Away'
      return response.to_json
    end
  end
end

# post is used when agent is working
post '/v1/agents/:uuid/heartbeat' do
  if params[:uuid].nil?
    status 200
    {
        Status: 200,
        Type: 'Error',
        Message: 'Missing UUID'
    }.to_json
  else
    jdata = JSON.parse(request.body.read)
    puts jdata['taskqueue_id']
    puts jdata['agent_status']

    # check on status of agents task
    taskqueue = Taskqueues.first(id: jdata['taskqueue_id'])

    if taskqueue.status == 'Canceled'
      msg = 'Canceled'
    else
      msg = 'OK'
    end

    {
        Status: 200,
        Type: 'Message',
        Taskqueue_id: taskqueue.id,
        Taskqueue_status: taskqueue.status,
        Message: msg
    }.to_json
  end
end

get '/v1/agents/:uuid/authorize' do
  if params[:uuid].nil?
    status 200
    {
        Status: 200,
        Type: 'Error',
        Message: 'Missing UUID'
    }.to_json
  else
    agent = Agents.first(:uuid => params[:uuid])
  end

  if !agent.nil?
    if agent.status == "Authorized"
      agent.status = "Online"
      agent.heartbeat = Time.now
      agent.save
      {
        Status: 200,
        Type: 'Message',
        Message: 'Authorized'
      }.to_json
    end
  else
    status 200
    {
        Status: 200,
        Type: 'Error',
        Message: 'Not Authorized'
    }.to_json
  end
end