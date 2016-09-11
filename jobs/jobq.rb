require 'resque'
require 'dm-mysql-adapter'
require 'data_mapper'
require './model/master.rb'
require 'benchmark'

def updateDbStatus(id, status)
  jobtask = Jobtasks.first(id: id)
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
    if jt.status == 'Queued' || jt.status == 'Running'
      job.status = status
      job.save
      done = false
      break
    end
  end
  # toggle job status
  if done == true
    job.status = 'Completed'
    job.save
  end
end

def updateDbRunTime(id, run_time)
  jobtask = Jobtasks.first(id: id)
  jobtask.run_time = run_time
  jobtask.save
end

module Jobq
  @queue = :hashcat

  def self.perform(id, cmd)
    jobtasks = Jobtasks.first(id: id)

    puts '===== creating hash_file ======='
    targets = Targets.all(jobid: jobtasks.job_id, cracked: false, fields: [:originalhash])
    hash_file = 'control/hashes/hashfile_' + jobtasks.job_id.to_s + '_' + jobtasks.task_id.to_s + '.txt'
    File.open(hash_file, 'w') do |f|
      targets.each do |entry|
        f.puts entry.originalhash
      end
      f.close
    end

    puts '===== Hash_File Created ======'

    puts '===== starting job ======='
    updateDbStatus(id, 'Running')
    puts id
    puts cmd
    run_time = Benchmark.realtime do
      system(cmd)
    end
    puts 'job completed'
    puts "And it only took: #{run_time} seconds"

    # this assumes a job completed successfully. we need to add check for failures or killed processes
    puts '==== Importing cracked hashes ====='
    jobtasks = Jobtasks.first(id: id)
    crack_file = 'control/outfiles/hc_cracked_' + jobtasks.job_id.to_s + '_' + jobtasks.task_id.to_s + '.txt'

    unless File.zero?(crack_file)
      File.open(crack_file).each_line do |line|
        hash_pass = line.split(/:/)
        plaintext = hash_pass[1]
        plaintext = plaintext.chomp

        # This will pull all hashes from DB regardless of job id
        records = Targets.all(fields: [:id, :cracked, :originalhash], originalhash: hash_pass[0], cracked: 0)
        # Yes its slow... we know.
        records.each do |entry|
          entry.cracked = 1
          entry.plaintext = plaintext
          entry.save
        end
      end
    end

   puts '==== import complete ===='

    begin
      File.delete(crack_file)
      File.delete(hash_file)

    rescue SystemCallError
      p 'ERROR: ' + $!
    end

    puts '==== Crack File Deleted ===='

    updateDbStatus(id, 'Completed')
    updateDbRunTime(id, run_time)
  end
end
