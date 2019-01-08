def isBusy?
  @jobs = Jobs.first(status: 'running')
  return true unless @jobs.nil?
end

def isDevelopment?
  Sinatra::Base.development?
end

def isOldVersion?
  # Check to see what version the app is at
  application_version = File.open('VERSION', &:readline)
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
        jobtask = Jobtasks.first(id: jobtask_id)
        if jobtask.keyspace_pos.to_i >= jobtask.keyspace.to_i
          updateJobTaskStatus(jobtask_id, 'Completed')
        end
      end
    end
  end
end

def updateJobTaskStatus(jobtask_id, status)

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

  # Send email
  if job.notify_completed == true && done == true
    puts '===== Sending Email ====='
    user = User.first(username: job.owner)
    hashfile = Hashfiles.first(id: job.hashfile_id)
    customer = Customers.first(id: job.customer_id)
    @hash_ids = []
    Hashfilehashes.where(hashfile_id: hashfile.id).each do |entry|
      @hash_ids.push(entry.hash_id)
    end
    total_cracked = Hashes.where(id: @hash_ids, cracked: 1).count
    total = Hashes.where(id: @hash_ids, cracked: 0).count
    if user.email
      sendEmail(user.email, "Your Job: #{job.name} for #{customer.name} has completed.", "#{user.username},\r\n\r\nHashview completed cracking #{hashfile.name}.\r\n\r\nTotal Cracked: #{total_cracked}.\r\nTotal Remaining: #{total}.")
    end
    puts '===== Email Sent ====='
  end

  # toggle job status
  if done
    job.status = 'Completed'
    job.ended_at = Time.now
    job.save

    # Calculate time difference and update hashfile
    hashfile = Hashfiles.first(id: job.hashfile_id)
    hashfile.total_run_time += (job.ended_at.to_i - job.started_at.to_i)
    hashfile.save

    # purge all queued tasks
    @taskqueues = HVDB[:taskqueues]
    @taskqueues.filter(job_id: job.id).delete

  end
  true
end
