def isBusy?
  @results = `ps awwux | grep -i Hashcat | egrep -v "(grep|sudo|resque|^$)"`
  return true if @results.length > 1
end

def isDevelopment?
  Sinatra::Base.development?
end

def isOldVersion?

  db_version = 'null'
  # Check to see what version the app is at
  application_version = File.open('VERSION') {|f| f.readline}
  puts 'APPLICATION VERSION: ' + application_version.to_s
  application_version = application_version.to_i

  # Check for v0.5.1
  # Note this version does not have a versions table. Going forward we will check that value
  has_version_column = false
  @tables = repository(:default).adapter.select('SHOW TABLES')
  @tables.each do | row |
    if row['Tables_in_hashview'] == 'version'
      has_version_column true
    end
  end
  
  if has_version_column == true
    db_version = settings.first(fields: [:version], id: params[:hashfile_id]).version.to_i
    puts 'DB:VERSION ' + db_version.to_s
    if Gem::Version.new(db_version) < Gem::Version.new(application_version)
      return true
    else
      return false
    end
  else
    puts 'No version column found. Assuming Version 0.5.1'
    return true
  end

end

def updateTaskqueueStatus(taskqueue_id, status, agent_id)
  queue = Taskqueues.first(id: taskqueue_id)
  queue.status = status
  queue.agent_id = agent_id
  queue.save
end


def updateJobTaskStatus(jobtask_id, status)

  jobtask = Jobtasks.first(id: jobtask_id)
  jobtask.status = status
  jobtask.save

  # if this is the last task for this current job, then set the job to be completed
  # find the job of the jobtask id:
  job = Jobs.first(id: jobtask.job_id)
  if job.status == 'Queued'
    job.status = 'Running'
    job.save
  end
  # find all tasks for current job:
  jobtasks = Jobtasks.all(job_id: job.id)
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
    user = User.first(username: job.last_updated_by)
    hashfile = Hashfiles.first(id: job.hashfile_id)
    customer = Customers.first(id: job.customer_id)
    @hash_ids = Set.new
    Hashfilehashes.all(hashfile_id: hashfile.id).each do |entry|
      @hash_ids.add(entry.hash_id)
    end
    total_cracked = Hashes.count(id: @hash_ids, cracked: 1)
    total = Hashes.count(id: @hash_ids, cracked: 0)
    if user.email
      sendEmail(user.email, "Your Job: #{job.name} for #{customer.name} has completed.", "#{user.username},\r\n\r\nHashview completed cracking #{hashfile.name}.\r\n\r\nTotal Cracked: #{total_cracked}.\r\nTotal Remaining: #{total}.")
    end
    puts '===== Email Sent ====='
  end

  # toggle job status
  if done == true
    job.status = 'Completed'
    job.save
    # purge all queued tasks
    taskqueues = Taskqueues.all(job_id: job.id)
    taskqueues.destroy
  end
end
