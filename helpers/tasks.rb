helpers do
  def assignTasksToJob(tasks, job_id)
    tasks.each do |task_id|
      jobtask = Jobtasks.new
      jobtask.job_id = job_id
      jobtask.task_id = task_id
      jobtask.save
    end
  end
end
