def isBusy?
  @jobs = Jobs.first(status: 'running')
  return true unless @jobs.nil?
end

def isDevelopment?
  Sinatra::Base.development?
end

def isOldVersion?

  # Check to see what version the app is at
  application_version = File.open('VERSION') {|f| f.readline}
  puts 'APPLICATION VERSION: ' + application_version.to_s
  # application_version = application_version.to_i

  # Check for v0.5.1
  # Note this version does not have a versions column. Going forward we will check that value
  has_version_column = false
  if Settings.columns.include?(:version)
    has_version_column = true
  end

  if has_version_column
    @settings = Settings.first
    db_version = @settings.version
    puts 'DB:VERSION ' + db_version.to_s
    if Gem::Version.new(db_version) < Gem::Version.new(application_version)
      return true
    else
      return false
    end
  else
    puts 'No version column found. Assuming Version 0.5.1'
    true
  end
end

def updateTaskqueueStatus(taskqueue_id, status, agent_id)
  queue = Taskqueues.first(id: taskqueue_id)
  if queue
    queue.status = status
    queue.agent_id = agent_id
    queue.save
    # if we are setting a status to completed, check to see if this is the last task in queue. if so, set jobtask to completed
    if status == 'Completed'
      jobtask_id = queue.jobtask_id
      queue.destroy
      remaining_queued_tasks = Taskqueues.where(jobtask_id: jobtask_id, status: 'Queued').all
      remaining_running_tasks = Taskqueues.where(jobtask_id: jobtask_id, status: 'Running').all
      remaining_importing_tasks = Taskqueues.where(jobtask_id: jobtask_id, status: 'Importing').all
      if remaining_queued_tasks.empty? && remaining_running_tasks.empty? && remaining_importing_tasks.empty?
        p 'Was this our last chunk?'
        jobtask = Jobtasks.first(id: jobtask_id)
        if jobtask.keyspace_pos.to_i >= jobtask.keyspace.to_i
          'Yup, looks like this is it bois.'
          updateJobTaskStatus(jobtask_id, 'Completed')
        end
      end
    end
  end
end

#def updateChunkQueueStatus(agent_queue_id, status, agent_id)
#
#  queue = Chunkqueues.first(id: agent_queue_id)
#  if queue
#    queue.status = status
#    queue.agent_id = agent_id
#    queue.save

    # if we are setting a status to completed, check to see if this is the last task in queue.
#    if status == 'Completed'
#      remaining_queued_chunks = Chunkqueues.where(task_queue_id: queue.task_queue_id, status: 'Queued')
#      remaining_running_chunks = Chunkqueues.where(task_queue_id: queue.task_queue_id, status: 'Running')
#      remaining_importing_chunks = Chunkqueues.where(task_queue_id: queue.task_queue_id, status: 'Importing')

#      p 'remaining queued chunks: ' + remaining_queued_chunks.to_s
#      p 'remaining running chunks: ' + remaining_running_chunks.to_s
#      p 'remaining importing chunks: ' + remaining_importing_chunks.to_s

      # If no other Chunk task is 'active'
#      if remaining_queued_chunks.empty? && remaining_running_chunks.empty? && remaining_importing_chunks.empty?
        # Check to see if the taskqueue entry is complete
#        task_queue_entry = Taskqueues.first(id: queue.task_queue_id)
#        p 'task queue entry: ' + task_queue_entry.to_s
#        p 'queue: ' + queue.task_queue_id.to_s
#        if task_queue_entry
#          p 'Was this our last chunk?'
#          if task_queue_entry.keyspace_pos.to_i >= task_queue_entry.keyspace.to_i
#            p 'Yes this was my last chunk.'
            # At this point, no more chunks exists for this task
            # and
            # there are no more key space (chunks) left to complete

            # Update Taskqueue and remove all entries from chunk queue
#            chunk_queue_entries = HVDB[:chunkqueues]
#            chunk_queue_entries.filter(task_queue_id: queue.task_queue_id).delete

#            task_queue_entry.status = 'Completed'
#            task_queue_entry.save

            # Next we check to see if we're the last task in the queue for this job
#            remaining_queued_tasks = Taskqueues.where(job_id: task_queue_entry.job_id, status: 'Queued').all
#            remaining_running_tasks = Taskqueues.where(job_id: task_queue_entry.job_id, status: 'Running').all
#            remaining_importing_tasks = Taskqueues.where(job_id: task_queue_entry.job_id, status: 'Importing').all
#            if remaining_queued_tasks.empty? && remaining_running_tasks.empty? && remaining_importing_tasks.empty?
#              updateJobTaskStatus(task_queue_entry.jobtask_id, 'Completed')
#            end
#          end
#        end
#      end
#    end
#  end
#end

def updateJobTaskStatus(jobtask_id, status)

  p 'updateJobTaskStatus: line 113'
  p 'jobtask_id: ' + jobtask_id.to_s
  p 'status: ' + status.to_s
  jobtask = Jobtasks.first(id: jobtask_id)
  jobtask.status = status
  jobtask.save

  # if this is the last task for this current job, then set the job to be completed
  # find the job of the jobtask id:
  job = Jobs.first(id: jobtask[:job_id])
  if job.status == 'Queued'
    job.status = 'Running'
    job.started_at = Time.now
    job.save
  end
  p 'updateJobTaskStatus: line 128'
  # find all tasks for current job:
  jobtasks = Jobtasks.where(job_id: job[:id]).all
  # if no more job are set to queue, consider the job completed
  done = true
  jobtasks.each do |jt|
    # if a jobtask equals one of these statuses we are not done
    if jt.status == 'Queued' || jt.status == 'Running' || jt.status == 'Importing'
      done = false
      break
    end
  end
  p 'updateJobTaskStatus: line 140'
  # Send email
  if job.notify_completed == true && done == true
    puts '===== Sending Email ====='
    user = User.first(username: job.last_updated_by)
    hashfile = Hashfiles.first(id: job.hashfile_id)
    customer = Customers.first(id: job.customer_id)
    @hash_ids = Set.new
    Hashfilehashes.where(hashfile_id: hashfile.id).each do |entry|
      @hash_ids.add(entry.hash_id)
    end
    total_cracked = Hashes.count(id: @hash_ids, cracked: 1)
    total = Hashes.count(id: @hash_ids, cracked: 0)
    if user.email
      sendEmail(user.email, "Your Job: #{job.name} for #{customer.name} has completed.", "#{user.username},\r\n\r\nHashview completed cracking #{hashfile.name}.\r\n\r\nTotal Cracked: #{total_cracked}.\r\nTotal Remaining: #{total}.")
    end
    puts '===== Email Sent ====='
  end
  p 'updateJobTaskStatus: line 158'
  # toggle job status
  if done
    job.status = 'Completed'
    job.ended_at = Time.now
    job.save

    # Calculate time difference and update hashfile
    hashfile = Hashfiles.first(id: job.hashfile_id)
    hashfile.total_run_time += (job.ended_at.to_i - job.started_at.to_i)
    hashfile.save
    p 'updateJobTaskStatus: line 169'
    # purge all queued tasks
    @taskqueues = HVDB[:taskqueues]
    @taskqueues.filter(job_id: job.id).delete

  end
  true
end

def hubEnabled?
  # Returns true if hub is enabled, and status is registered
  hub_settings = HubSettings.first
  hub_settings.status == 'registered' ? true : false
end
