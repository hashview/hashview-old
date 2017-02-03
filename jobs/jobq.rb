require 'resque'
require 'dm-mysql-adapter'
require 'data_mapper'
#require './model/master.rb'
require 'benchmark'
#require './helpers/email.rb'

def updateDbStatus(id, status)
  # require './helpers/email.rb'

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

def updateDbRunTime(job_id, hashfile_id, run_time)
  jobtask = Jobtasks.first(id: job_id)
  jobtask.run_time = run_time
  jobtask.save

  hashfile = Hashfiles.first(id: hashfile_id)
  hashfile.total_run_time = hashfile.total_run_time + run_time.to_i
  hashfile.save
end

# Responsible for managing crack jobs
module Jobq
  @queue = :hashcat

  def self.perform(id, cmd)
    jobtasks = Jobtasks.first(id: id)
    job = Jobs.first(id: jobtasks.job_id)

    unless job.status == 'Canceled'

      puts '===== creating hash_file ======='
      #targets = Targets.all(hashfile_id: job.hashfile_id, cracked: false, fields: [:originalhash])
      @hash_ids = Set.new
      Hashfilehashes.all(fields: [:hash_id], hashfile_id: job.hashfile_id).each do |entry|
        @hash_ids.add(entry.hash_id)
      end
      targets = Hashes.all(fields: [:originalhash], id: @hash_ids, cracked: 0)

      hash_file = 'control/hashes/hashfile_' + jobtasks.job_id.to_s + '_' + jobtasks.task_id.to_s + '.txt'
      #hashtype_target = Targets.first(hashfile_id: job.hashfile_id, fields: [:hashtype])
      hashtype_target = Hashes.first(id: @hash_ids)
      hashtype = hashtype_target.hashtype.to_s

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

      puts '===== starting job ======='
      updateDbStatus(id, 'Running')
      # puts id
      puts cmd
      run_time = Benchmark.realtime do
        system(cmd)
      end
      puts 'job completed'
      puts "And it only took: #{run_time} seconds"

      # this assumes a job completed successfully. we need to add check for failures or killed processes
      puts '==== Importing cracked hashes ====='
      updateDbStatus(id, 'Importing')
      jobtasks = Jobtasks.first(id: id)
      crack_file = 'control/outfiles/hc_cracked_' + jobtasks.job_id.to_s + '_' + jobtasks.task_id.to_s + '.txt'

      unless File.zero?(crack_file)
        File.open(crack_file).each_line do |line|
          hash_pass = line.split(/:/)
          plaintext = hash_pass[-1] # Get last entry
          plaintext = plaintext.chomp
          # Handle salted hashes 
          # Theres gotta be a better way to do this
          if hashtype == '10' or hashtype == '20' or hashtype == '30' or hashtype == '40' or hashtype == '50' or hashtype == '60' or hashtype == '110' or hashtype == '120' or hashtype == '130' or hashtype == '140' or hashtype == '150' or hashtype == '160' or hashtype == '1100' or hashtype == '1410' or hashtype == '1420' or hashtype == '1430' or hashtype == '1440' or hashtype == '1450' or hashtype == '1460' or hashtype == '2611' or hashtype == '2711'
            hash = hash_pass[0].to_s + ':' + hash_pass[1].to_s
          elsif hashtype == '5500'
            hash = hash_pass[3] + ':' + hash_pass[4] + ':' + hash_pass[5]
          elsif hashtype == '5600'
            hash = hash_pass[0].to_s + ':' + hash_pass[1].to_s + ':' + hash_pass[2].to_s + ':' + hash_pass[3].to_s + ':' + hash_pass[4].to_s + ':' + hash_pass[5].to_s
          else
            hash = hash_pass[0]
          end

          # This will pull all hashes from DB regardless of job id
          #records = Targets.all(fields: [:id, :cracked, :plaintext], originalhash: hash, cracked: 0)
          records = Hashes.all(fields: [:id, :cracked, :plaintext, :lastupdated], originalhash: hash, cracked: 0 )
          # Yes its slow... we know.
          records.each do |entry|
            entry.cracked = 1
            entry.lastupdated = Time.now
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
      updateDbRunTime(id, job.hashfile_id, run_time)
    end
  end
end
