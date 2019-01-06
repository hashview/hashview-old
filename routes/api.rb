# my shameful attempt at implementing a REST API

get '/v1/notauthorized' do
  {
    status: 200,
    type: 'Error',
    msg: 'Your agent is not authorized to work with this cluster.'
  }.to_json
end

# our main worker queue
get '/v1/queue' do
  # is agent authorized
  redirect to('/v1/notauthorized') unless agentAuthorized(request.cookies['agent_uuid'])

  # grab next task to be performed
  @queue = Taskqueues.first(status: 'Queued')
  if @queue
    return @queue.to_a.to_json
  else
    status 200
    {
      status: 200,
      type: 'Error',
      msg: 'There are no items on the queue to process'
    }.to_json
  end
end

# force or restart a queue item
# used when agent goes offline and comes back online
# without a running hashcat cmd while task still assigned to them
get '/v1/queue/:id' do
  # is agent authorized
  redirect to('/v1/notauthorized') unless agentAuthorized(request.cookies['agent_uuid'])

  # get agent id from uuid in cookie
  uuid = request.cookies['agent_uuid']

  if uuid
    agent = Agents.first(uuid: uuid)
    if agent
      # assign chunk from queue only if agent id is already assigned
      assigned_chunk = Taskqueues.first(id: params[:id], agent_id: agent.id)
    end
  else
    status 200
    {
      status: 200,
      type: 'Error',
      msg: 'Missing UUID'
    }.to_json
  end

  # check to see if this agent is suppose to be working on something
  return assigned_chunk.to_json if assigned_chunk
end

# remove item from queue
get '/v1/queue/:id/remove' do
  # is agent authorized
  redirect to('/v1/notauthorized') unless agentAuthorized(request.cookies['agent_uuid'])

  @queue = Taskqueues.first(id: params[:id])
  @queue.destroy
  return
end

# update status of task_queue item
post '/v1/queue/:taskqueue_id/status' do
  # is agent authorized
  redirect to('/v1/notauthorized') unless agentAuthorized(request.cookies['agent_uuid'])

  jdata = JSON.parse(request.body.read)
  agent = Agents.first(uuid: jdata['agent_uuid'])

  updateTaskqueueStatus(params[:taskqueue_id], jdata['status'], agent.id)
end

# update status of job
post '/v1/jobtask/:jobtask_id/status' do
  # is agent authorized
  redirect to('/v1/notauthorized') unless agentAuthorized(request.cookies['agent_uuid'])
  jdata = JSON.parse(request.body.read)
  updateJobTaskStatus(jdata['jobtask_id'], jdata['status'])
end

# return task details
get '/v1/task/:id' do
  # is agent authorized
  redirect to('/v1/notauthorized') unless agentAuthorized(request.cookies['agent_uuid'])

  task = Tasks.first(id: params[:id])
  return task.to_json
end

# return jobtask details
get '/v1/jobtask/:id' do
  # is agent authorized
  redirect to('/v1/notauthorized') unless agentAuthorized(request.cookies['agent_uuid'])

  jobtask = Jobtasks.first(id: params[:id])
  return jobtask.to_json
end

# provide job info
get '/v1/job/:id' do
  # is agent authorized
  redirect to('/v1/notauthorized') unless agentAuthorized(request.cookies['agent_uuid'])

  @job = Jobs.first(id: params[:id])
  return @job.to_json
end

# provide wordlist info
get '/v1/wordlist' do
  # is agent authorized
  redirect to('/v1/notauthorized') unless agentAuthorized(request.cookies['agent_uuid'])

  wordlists = Wordlists.all
  data = {}
  data['wordlists'] = wordlists
  return data.to_json
end

# serve a wordlist
get '/v1/wordlist/:id' do
  # is agent authorized
  redirect to('/v1/notauthorized') unless agentAuthorized(request.cookies['agent_uuid'])

  wordlist = Wordlists.first(id: params[:id])
  wordlist_orig = wordlist.path.split('/')[-1]
  cmd = "gzip -9 -k -c control/wordlists/#{wordlist_orig} > control/tmp/#{wordlist_orig}.gz"
  p 'cmd: ' + cmd.to_s
  # Execute our compression
  `#{cmd}`
  # Serve File
  send_file "control/tmp/#{wordlist_orig}.gz", :type => 'application/octet-stream', :filename => "#{wordlist_orig}.gz"
end

# Get info on a wordlist by jobtask id
get 'v1/wordlist/by_jobtask_id/:id' do
  # is agent authorized
  redirect to('/v1/notauthorized') unless agentAuthorized(request.cookies['agent_uuid'])

  # First we have to get the jobtask
  jobtask = Jobtasks.first(id: params[:id])

  # Next we have to get the task
  task = Tasks.first(id: jobtask.task_id)

  # finally we can get the wordlist info
  wordlist = Wordlists.first(id: task.wl_id)

end

get '/v1/updateWordlist/:wl_id' do
  # is agent authorized
  redirect to('/v1/notauthorized') unless agentAuthorized(request.cookies['agent_uuid'])

  updateDynamicWordlist(params[:wl_id])
  data = {
    status: 200,
    type: 'message',
    msg: 'OK'
  }
  return data.to_json
end

# provide Rules file info
get '/v1/rules' do
  # is agent authorized
  redirect to('/v1/notauthorized') unless agentAuthorized(request.cookies['agent_uuid'])

  rules = Rules.all
  data = {}
  data['rules'] = rules
  return data.to_json
end

# serve a Rules File
get '/v1/rules/:id' do
  # is agent authorized
  redirect to('/v1/notauthorized') unless agentAuthorized(request.cookies['agent_uuid'])

  rules = Rules.first(id: params[:id])
  send_file rules.path, :type => 'application/octet-stream', :filename => rules.path.split('/')[-1]
end

# generate and serve hashfile
# TODO: make this a background worker in resque
get '/v1/jobtask/:jobtask_id/hashfile/:hashfile_id' do
  # is agent authorized
  redirect to('/v1/notauthorized') unless agentAuthorized(request.cookies['agent_uuid'])

  jobtask_id = params[:jobtask_id]
  hashfile_id = params[:hashfile_id]

  # we need jobtask info to make hashfile path
  jobtasks = Jobtasks.first(id: jobtask_id)

  @hash_ids = Set.new
  Hashfilehashes.where(hashfile_id: hashfile_id).select(:hash_id).each do |entry|
    @hash_ids.add(entry.hash_id)
  end
  targets = Hashes.where(id: @hash_ids.to_a, cracked: 0).select(:originalhash).all

  hash_file = 'control/hashes/hashfile_' + jobtasks.job_id.to_s + '_' + jobtasks.task_id.to_s + '.txt'
  hashtype_target = Hashes.first(id: @hash_ids.to_a)
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

  send_file hash_file

end

# accept uploaded crack files
post '/v1/jobtask/:jobtask_id/crackfile/upload' do
  # is agent authorized
  redirect to('/v1/notauthorized') unless agentAuthorized(request.cookies['agent_uuid'])

  tmpfile = "control/tmp/#{rand.to_s[2..2048]}.txt"
  # puts "[+] Agent uploaded crack file. Saving to: #{tmpfile}"
  File.open(tmpfile, 'wb') do |f|
    f.write(params[:file][:tempfile].read)
  end
  importCracked(params[:jobtask_id], tmpfile, params[:runtime])
  return 'upload successful'
end

# accept upload hashcat status
# TODO complete this
post '/v1/hcoutput/status' do
  # is agent authorized
  redirect to('/v1/notauthorized') unless agentAuthorized(request.cookies['agent_uuid'])

  return request.body.read
end


# post is used when agent is working
post '/v1/agents/:uuid/heartbeat' do
  varWash(params)

  # error if no uuid is set in cookie
  if params[:uuid].nil?
    status 200
    {
      status: 200,
      type: 'Error',
      msg: 'Missing UUID'
    }.to_json
  else
    # read payload data
    payload = JSON.parse(request.body.read)

    # get agent data from db if available
    agent = Agents.first(uuid: params[:uuid])
    if !agent.nil?
      # We have an Agent in our agents table
      if agent.status == 'Authorized'
        # if agent is set to authorized, continue to authorization process
        redirect to("/v1/agents/#{params[:uuid]}/authorize")
      elsif agent.status == 'Pending'
        # agent exists, but has been deactivated. update heartbeat and turn agent away
        agent.src_ip = "#{request.ip}"
        agent.heartbeat = Time.now
        agent.save
        {
          status: 200,
          type: 'message',
          msg: 'Go Away'
        }.to_json
      elsif agent.status == 'Syncing'
        agent.heartbeat = Time.now
        agent.save
        {
          status: 200,
          type: 'message',
          msg: 'OK'
        }.to_json
      else
        # agent already exists and is should be authorized by now
        redirect to('/v1/notauthorized') unless agentAuthorized(request.cookies['agent_uuid'])

        # is agent working?
        if payload['agent_status'] == 'Working'
          # read hashcat output and compare against job we think it should be working on
          agent_task = payload['agent_task']
          task_queue = Taskqueues.first(id: agent_task, agent_id: agent.id)

          # update db with the agents hashcat status
          if payload['hc_status']
            #puts payload['hc_status']
            agent.status = payload['agent_status']
            agent.hc_status = payload['hc_status'].to_json
            payload['hc_status'].each do |item|
              if item.to_s =~ /Speed Dev #/
                agent.benchmark = item[1].split(' ')[0].to_s + ' ' + item[1].split(' ')[1].to_s
              end
            end
            agent.save
          end

          if task_queue.nil? || task_queue.status == 'Canceled'
            {
              status: 200,
              type: 'message',
              msg: 'Canceled'
            }.to_json
          else
            agent.heartbeat = Time.now
            agent.status = payload['agent_status']
            agent.save
            {
              status: 200,
              type: 'message',
              msg: 'OK'
            }.to_json
          end

        elsif payload['agent_status'] == 'Idle'
          # assign work to agent

          # get next task_queue item for this agent if there is anything in the queue
          already_assigned_chunk = Taskqueues.first(agent_id: agent.id)
          if already_assigned_chunk and !already_assigned_chunk.nil?
            response = {}
            response['status'] = 200
            response['type'] = 'message'
            response['msg'] = 'START'
            response['task_id'] = already_assigned_chunk.id
            return response.to_json
          else
            # Agent doesn't have anything to do. Lets carve it a chunk
            # 1) Figure out how much this guy can eat
            benchmark = agent.benchmark
            # Convert to H/s
            speed = 0
            if benchmark =~ / H\/s/
              speed = benchmark.split[0].to_f
            elsif benchmark =~ /kH\/s/
              speed = benchmark.split[0].to_f
              speed *= 1000
            elsif benchmark =~ /MH\/s/
              speed = benchmark.split[0].to_f
              speed *= 1000000
            elsif benchmark =~ /GH\/s/
              speed = benchmark.split[0].to_f
              speed *= 1000000000
            elsif benchmark =~ /TH\/s/
              speed = benchmark.split[0].to_f
              speed *= 1000000000000
            end

            # Fudge by factor of ten to ensure no to small of chunking
            speed *= 100

            # if dynamic chunking is disabled use staticly assigned chunk
            @settings = Settings.first
            speed = @settings.chunk_size.to_i unless @settings.use_dynamic_chunking == '1'

            # if for whatever reason we dont have a value for speed set it here.
            speed = 50000 if speed.zero?

            # First lets see if there's any active task queue items we can help with
            @jobtask_queue = Jobtasks.where(status: 'Running').all
            if @jobtask_queue && !@jobtask_queue.empty? # useing.empty since we're doing a where / all select

              @jobtask_queue.each do |jobtask_queue_entry|
                task = Tasks.first(id: jobtask_queue_entry.task_id)
                # We only want to hand out chunks for masks and dictionary tasks
                # i.e. no subdivision for bruteforce
                if task.hc_attackmode == 'maskmode' || task.hc_attackmode == 'dictionary'
                  # Lets update the keyspace for these tasks
                  # This is especially important for dictionary tasks using dynamic dictionaries
                  wordlist = Wordlists.first(id: task.wl_id)
                  updateDynamicWordlist(wordlist.id) if wordlist && wordlist.type == 'dynamic'
                  task.keyspace = getKeyspace(task) if wordlist && wordlist.type == 'dynamic'
                  task.save

                  # Requery to get up-to-date value
                  task = Tasks.first(id: jobtask_queue_entry.task_id)
                  jobtask_queue_entry.keyspace = task.keyspace
                  jobtask_queue_entry.save

                  # Now lets see if there's any jobtasks left where there's a chunk to be made

                  if jobtask_queue_entry.keyspace_pos.to_i < task.keyspace.to_i
                    # There's still work to be done

                    crack_command = jobtask_queue_entry.command
                    # Do we care if the mode is dictionary or mask, or do we do it all?
                    crack_command += ' -s ' + jobtask_queue_entry.keyspace_pos.to_i.to_s
                    crack_command += ' -l ' + speed.to_i.to_s
                    crack_command += ' | tee -a control/outfiles/hcoutput_'
                    crack_command += jobtask_queue_entry.job_id.to_s
                    crack_command += '_'
                    crack_command += jobtask_queue_entry.task_id.to_s
                    crack_command += '.txt'

                    # Update pos
                    if jobtask_queue_entry.keyspace_pos.to_i + speed.to_i > task.keyspace.to_i
                      jobtask_queue_entry.keyspace_pos = task.keyspace
                    else
                      jobtask_queue_entry.keyspace_pos += speed
                    end
                    jobtask_queue_entry.save

                    # Create new agent task command
                    task_queue_entry = Taskqueues.new
                    task_queue_entry.job_id = jobtask_queue_entry.job_id
                    task_queue_entry.jobtask_id = jobtask_queue_entry.id
                    task_queue_entry.status = 'Queued'
                    task_queue_entry.agent_id = agent.id
                    task_queue_entry.command = crack_command
                    task_queue_entry.save

                    # return to agent chunk_queue id
                    response = {}
                    response['status'] = 200
                    response['type'] = 'message'
                    response['msg'] = 'START'
                    response['task_id'] = task_queue_entry.id
                    return response.to_json
                  end
                end
              end
            end

            # Looks like there are no running jobtasks, time to start a new one
            jobtask_queue_entry = Jobtasks.first(status: 'Queued')
            if jobtask_queue_entry && !jobtask_queue_entry.nil? # using nil since we're doing a single line select

              task = Tasks.first(id: jobtask_queue_entry.task_id)
              crack_command = jobtask_queue_entry.command
              if task.hc_attackmode == 'maskmode' || task.hc_attackmode == 'dictionary'
                wordlist = Wordlists.first(id: task.wl_id)
                updateDynamicWordlist(wordlist.id) if wordlist && wordlist.type == 'dynamic'
                task.keyspace = getKeyspace(task) if wordlist && wordlist.type == 'dynamic'
                task.save
                task = Tasks.first(id: jobtask_queue_entry.task_id)
                jobtask_queue_entry.keyspace = task.keyspace
                jobtask_queue_entry.keyspace_pos = 0
                jobtask_queue_entry.save

                if jobtask_queue_entry.keyspace_pos.to_i < task.keyspace.to_i
                  crack_command += ' -s 0 -l ' + speed.to_i.to_s

                  # Update pos
                  if jobtask_queue_entry.keyspace_pos.to_i + speed > task.keyspace.to_i
                    jobtask_queue_entry.keyspace_pos = task.keyspace
                  else
                    jobtask_queue_entry.keyspace_pos += speed
                  end
                  jobtask_queue_entry.save
                end
              end

              crack_command += ' | tee -a control/outfiles/hcoutput_'
              crack_command += jobtask_queue_entry.job_id.to_s
              crack_command += '_'
              crack_command += jobtask_queue_entry.task_id.to_s
              crack_command += '.txt'

              # Create new agent task command
              task_queue_entry = Taskqueues.new
              task_queue_entry.job_id = jobtask_queue_entry.job_id
              task_queue_entry.jobtask_id = jobtask_queue_entry.id
              task_queue_entry.status = 'Queued'
              task_queue_entry.agent_id = agent.id
              task_queue_entry.command = crack_command
              task_queue_entry.save

              # return to agent agentqueue id
              jobtask_queue_entry.status = 'Running'
              jobtask_queue_entry.save
              response = {}
              response['status'] = 200
              response['type'] = 'message'
              response['msg'] = 'START'
              response['task_id'] = task_queue_entry.id
              return response.to_json
            end

            # update agent heartbeat but do nothing for now
            agent.heartbeat = Time.now
            agent.status = payload['agent_status']
            agent.hc_status = ''
            agent.src_ip = "#{request.ip}"
            agent.save
            {
              status: 200,
              type: 'message',
              msg: 'OK'
            }.to_json
          end
        end
      end
    else
      # we didnt authorize this agent. it might be new
      newagent = Agents.new
      newagent.uuid = params[:uuid]
      newagent.name = params[:uuid]
      newagent.status = "Pending"
      newagent.src_ip = "#{request.ip}"
      newagent.heartbeat = Time.now
      newagent.save
      response = {}
      response['message'] = 'Go Away'
      return response.to_json
    end
  end
end

get '/v1/agents/:uuid/authorize' do
  if params[:uuid].nil?
    status 200
    {
      status: 200,
      type: 'Error',
      msg: 'Missing UUID'
    }.to_json
  else
    #TODO SECURITY - make sure this param is a formated as a valid uuid
    agent = Agents.first(uuid: params[:uuid])
  end

  if !agent.nil?
    if agent.status == "Authorized"
      agent.status = "Online"
      agent.heartbeat = Time.now
      agent.src_ip = "#{request.ip}"
      agent.save
      {
        status: 200,
        type: 'message',
        msg: 'Authorized'
      }.to_json
    end
  else
    status 200
    {
      status: 200,
      type: 'Error',
      msg: 'Not Authorized'
    }.to_json
  end
end

post '/v1/agents/:uuid/stats' do
  if params[:uuid].nil?
    status 200
    {
      status: 200,
      type: 'Error',
      msg: 'Missing UUID'
    }.to_json
  else
    # is agent authorized
    redirect to('/v1/notauthorized') unless agentAuthorized(request.cookies['agent_uuid'])

    payload = JSON.parse(request.body.read)
    #puts payload

    agent = Agents.first(uuid: params[:uuid])
    agent.cpu_count = payload['cpu_count'].to_i
    agent.gpu_count = payload['gpu_count'].to_i
    agent.benchmark = payload['benchmark'].to_s
    agent.save

    {
      status: 200,
      type: 'message',
      msg: 'Stats received'
    }.to_json
  end
end

