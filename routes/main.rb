# encoding: utf-8
get '/' do
  @users = User.all
  
  if @users.empty?
    redirect to('/register')
  elsif !validSession?
    redirect to('/login')
  else
    redirect to('/home')
  end
end

get '/home' do


  @jobs = Jobs.all(order: [:queued_at.asc])
  @jobtasks = Jobtasks.all
  @tasks = Tasks.all
  @taskqueues = Taskqueues.all
  @agents = Agents.all
  @time_now = Time.now

  @customers = Customers.all
  @active_jobs = Jobs.all(fields: [:id, :status], status: 'Running')

  # JumboTron Display
  # Building out an array of hashes for the jumbotron display
  @jumbotron = []
  @jobs.each do |job|
    element = {}
    if job.status == 'Running' || job.status == 'importing'
      #@Customers = Customers.first(id: job.customer_id).each do |customer|
      @customers.each do |customer|
        if customer.id == job.customer_id.to_i
          element['customer_name'] = customer.name
        end
      end

      element['job_name'] = job.name

      @hash_ids = Array.new
      Hashfilehashes.all(fields: [:hash_id], hashfile_id: job.hashfile_id).each do |entry|
        @hash_ids.push(entry.hash_id)
      end

      hashfile_total = Hashes.count(id: @hash_ids)
      hashfile_cracked = Hashes.count(id: @hash_ids, cracked: 1)

      element['hashfile_cracked'] = hashfile_cracked
      element['hashfile_total'] = hashfile_total
      element['hashfile_progress'] = (hashfile_cracked.to_f / hashfile_total.to_f) * 100
      element['job_starttime'] = job.started_at

      time_now = Time.now
      if time_now.to_time - job.started_at.to_time > 86400
        element['job_runtime'] = ((time_now.to_time - job.started_at.to_time).to_f / 86400).round(2).to_s + ' Days'
      elsif time_now.to_time - job.started_at.to_time > 3600
        element['job_runtime'] = ((time_now.to_time - job.started_at.to_time).to_f / 3600).round(2).to_s + ' Hours'
      elsif time_now.to_time - job.started_at.to_time > 60
        element['job_runtime'] = ((time_now.to_time - job.started_at.to_time).to_f / 60).round(2).to_s + ' Minutes'
      elsif time_now.to_time - job.started_at.to_time >= 0
        element['job_runtime'] = (time_now.to_time - job.started_at.to_time).to_f.round(2).to_s + ' Seconds'
      else
        element['job_runtime'] = 'Im ready coach, just send me in.'
      end

      total_speed = 0
      Taskqueues.all(job_id: job.id, status: 'Running').each do |queued_task|
        agent = Agents.first(id: queued_task.agent_id)

        if agent.benchmark
          # Normalizing Benchmark Speeds
          if agent.benchmark.include? ' H/s'
            speed = agent.benchmark.split[0].to_f
            total_speed += speed
          elsif agent.benchmark.include? 'kH/s'
            speed = agent.benchmark.split[0].to_f
            speed *= 1000
            total_speed += speed
          elsif agent.benchmark.include? 'MH/s'
            speed = agent.benchmark.split[0].to_f
            speed *= 1000000
            total_speed += speed
          elsif agent.benchmark.include? 'GH/s'
            speed = agent.benchmark.split[0].to_f
            speed *= 1000000000
            total_speed += speed
          elsif agent.benchmark.include? 'TH/s'
            speed = agent.benchmark.split[0].to_f
            speed *= 1000000000000
            total_speed += speed
          else
            total_speed += 0
          end
        end
      end

      # Convert to Human Readable Format
      if total_speed > 1000000000000
        element['job_crackrate'] = (total_speed.to_f / 1000000000000).round(2).to_s + ' TH/s'
      elsif total_speed > 1000000000
        element['job_crackrate'] = (total_speed.to_f / 1000000000).round(2).to_s + ' GH/s'
      elsif total_speed > 1000000
        element['job_crackrate'] = (total_speed.to_f / 1000000).round(2).to_s + ' MH/s'
      elsif total_speed > 1000
        element['job_crackrate'] = (total_speed.to_f / 1000).round(2).to_s + ' kH/s'
      elsif total_speed >= 0
        element['job_crackrate'] = total_speed.to_f.round(2).to_s + ' H/s'
      else
        element['job_crackrate'] = '0 H/s'
      end

      @jumbotron.push(element)
    end
  end

  haml :home
end