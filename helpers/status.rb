def isBusy?
  @results = `ps awwux | grep -i Hashcat | egrep -v "(grep|sudo|resque|^$)"`
  return true if @results.length > 1
end

def isDevelopment?
  Sinatra::Base.development?
end

def isOldVersion()
  begin
    if Targets.all
      return true
    else
      return false
    end
  rescue
    # we really need a better upgrade process
    return false
  end

def updateTaskqueueStatus(taskqueue_id, status)
  queue = Taskqueues.first(id: taskqueue_id)
  queue.status = status
  queue.save
end


def updateJobStatus(jobtask_id, status)
  # require './helpers/email.rb'

  jobtask = Jobtasks.first(id: jobtask_id)
  puts jobtask
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
  # if no more jobs are set to queue, consider the job completed
  done = true
  jobtasks.each do |jt|
    if jt.status == 'Queued' || jt.status == 'Running' || jt.status == 'Importing'
      job.status = status
      job.save
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
  end
end
