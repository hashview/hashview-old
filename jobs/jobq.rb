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
  # find all tasks for current job:
  jobtasks = Jobtasks.all(job_id: job.id)
  # if no more jobs are set to queue, consider the job completed
  done = true
  jobtasks.each do |jt|
    if jt.status == 'Queued' || jt.status == 'Running'
      job.status_detail = status
      job.save
      done = false
      break
    end
  end
  # toggle job status
  if done == true
    job.status = 0
    job.status_detail = 'Completed'
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

    results = []
    if !File.zero?(crack_file)
      File.open(crack_file).each_line do |line|
        results << line
      end

      @records = Targets.all(fields: [:id, :cracked, :originalhash])
      @records.each do |records_entry|
        if results.size == 0
          break
        end
        results.each do |results_entry|
          hash_pass = results_entry.split(/:/)
          if records_entry.originalhash == hash_pass[0]
            records_entry.cracked = 1
            plaintext = hash_pass[1]
            plaintext = plaintext.chomp
            records_entry.plaintext = plaintext
            records_entry.save
            results.delete(results_entry)
            break
          end
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
