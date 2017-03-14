# my shameful attempt at implementing a REST API

# our main worker queue
get '/v1/queue' do
  # grab next task to be performed
  @queue = Taskqueues.first(status: 'Queued')
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

# force or restart a queue item
# used when agent goes offline and comes back online
# without a running hashcat cmd while task still assigned to them
get '/v1/queue/:id' do
  # get agent id from uuid in cookie
  uuid = request.cookies['agent_uuid']

  if uuid
    @agent = Agents.first(uuid: uuid)
    if @agent
      # assign task from queue only if agent id is already assigned
      @assigned_task = Taskqueues.first(id: params[:id], agent_id: @agent.id)
    end
  else
    status 200
    {
        Status: 200,
        Type: 'Error',
        Message: 'Missing UUID'
    }.to_json
  end

  # check to see if this agent is suppose to be working on something
  if @assigned_task
    puts @assigned_task.to_json
    return @assigned_task.to_json
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
  puts "======================================="
  puts "[+] updating jobtask id: #{params['jobtask_id']} to status: #{jdata['status']}"
  updateJobTaskStatus(jdata['jobtask_id'], jdata['status'])
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

# # heartbeat
# get '/v1/agents/:uuid/heartbeat' do
#   response = Hash.new
#   if params[:uuid].nil?
#     status 200
#     {
#         Status: 200,
#         Type: 'Error',
#         Message: 'Missing UUID'
#     }.to_json
#   else
#     @agent = Agents.first(:uuid => params[:uuid])
#     if !@agent.nil?
#       if @agent.status == "Authorized"
#         redirect to("/v1/agents/#{params[:uuid]}/authorize")
#       else
#         # check to see if agent should be working on an already assigned task
#         @assigned_task = Taskqueues.first(status: 'Running', agent_id: @agent.id)
#         @agent.status = "Online"
#         @agent.heartbeat = Time.now
#         @agent.save
#         data = {}
#         data['Status'] = 200
#         data['Type'] = 'Message'
#         data['Message'] = 'OK'
#         if @assigned_task
#           data['Working'] = @assigned_task.id
#         end
#         return data.to_json
#       end
#     else
#       newagent = Agents.new
#       newagent.uuid = params[:uuid]
#       newagent.name = params[:uuid] + " (untrusted)"
#       newagent.status = "Pending"
#       newagent.src_ip = "#{request.ip}"
#       newagent.heartbeat = Time.now
#       newagent.save
#       response['Message'] = 'Go Away'
#       return response.to_json
#     end
#   end
# end

# post is used when agent is working
post '/v1/agents/:uuid/heartbeat' do
  # error if no uuid is set in cookie
  if params[:uuid].nil?
    status 200
    {
        Status: 200,
        Type: 'Error',
        Message: 'Missing UUID'
    }.to_json
  else
    # read payload data
    payload = JSON.parse(request.body.read)

    # get agent data from db if available
    @agent = Agents.first(:uuid => params[:uuid])
    if !@agent.nil?
      if @agent.status == 'Authorized'
        # if agent is set to authorized, continue to authorization process
        redirect to("/v1/agents/#{params[:uuid]}/authorize")
      else
        # agent already exists and is authorized to do work

        # is agent working?
        if payload['agent_status'] == 'Working'
          # read hashcat output and compare against job we think it should be working on
          agenttask = payload['agent_task']
          taskqueue = Taskqueues.first(id: agenttask, agent_id: @agent.id)
          puts taskqueue

          # update db with the agents hashcat status
          if payload['hc_status']
            puts payload['hc_status']
            @agent.hc_status = payload['hc_status'].to_json
            @agent.save
          end

          if taskqueue.nil? || taskqueue.status == 'Canceled'
            {
              status: 200,
              type: 'Message',
              msg: 'Canceled'
            }.to_json
          else
            @agent.heartbeat = Time.now
            @agent.save
            {
                status: 200,
                type: 'Message',
                msg: 'OK'
            }.to_json
          end

          # # are agent and server in sync
          # if agenttask.to_i == taskqueue.id
          #   # update heartbeat and save hc_output for ui
          #   @agent.heartbeat = Time.now
          #   @agent.save
          #   {
          #     status: 200,
          #     type: 'Message',
          #     msg: 'OK'
          #   }.to_json
          # else
          #   # server and agent are out of sync, tell agent to stop working
          #   {
          #     status: 200,
          #     type: 'Message',
          #     msg: 'Canceled'
          #   }.to_json
          # end

        elsif payload['agent_status'] == 'Idle'
          # assign work to agent

          # set next taskqueue item for this agent if there is anything in the queue
          already_assigned_task = Taskqueues.first(status: 'Running', agent_id: @agent.id)
          if already_assigned_task and !already_assigned_task.nil?
            taskqueue = already_assigned_task
          else
            taskqueue = Taskqueues.first(status: 'Queued', agent_id: nil)
          end

          if taskqueue and !taskqueue.nil?
            p "=========== assigning agent task id: #{taskqueue.id}"
            taskqueue.agent_id = @agent.id
            taskqueue.save

            {
              status: 200,
              type: 'Message',
              msg: 'START',
              task_id: "#{taskqueue.id}"
            }.to_json
          else
            # update agent heartbeat but do nothing for now
            p '########### I have nothing for you to do now ###########'
            @agent.heartbeat = Time.now
            @agent.save
            {
              status: 200,
              type: 'Message',
              msg: 'OK'
            }.to_json
          end
        end
      end
    else
      # we didnt authorize this agent. it might be new
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