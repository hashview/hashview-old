# updates run time for each hashfile after a job has completed
def updateDbRunTime(job_id, hashfile_id, run_time)
  jobtask = Jobtasks.first(id: job_id)
  jobtask.run_time = run_time
  jobtask.save

  hashfile = Hashfiles.first(id: hashfile_id)
  hashfile.total_run_time = hashfile.total_run_time + run_time.to_i
  hashfile.save
end

# imports the uploaded crackfile
def importCracked(id, crack_file, run_time)
  # this assumes a job completed successfully. we need to add check for failures or killed processes
  puts '==== Importing cracked hashes ====='

  # Disabling now that we are chunking. Not sure if this is a good idea yet
  #updateJobTaskStatus(id, 'Importing')

  jobtasks = Jobtasks.first(id: id)
  #crack_file = 'control/outfiles/hc_cracked_' + jobtasks.job_id.to_s + '_' + jobtasks.task_id.to_s + '.txt'
  job = Jobs.first(id: jobtasks.job_id)

  # determine hashfile path
  hash_file = 'control/hashes/hashfile_' + jobtasks.job_id.to_s + '_' + jobtasks.task_id.to_s + '.txt'

  # obtain the hashfile type (we always assume a crackfile will contain only one type of hashes)
  # this isnt the best approach. consider storing hashtype in hashfiles or extract hashtype when updating a row in hashes table
  hashfilehash = Hashfilehashes.first(hashfile_id: job.hashfile_id)
  # hashfilehashes doesnt store hashtype, so obtain it from hashes table
  hashtype = Hashes.first(id: hashfilehash.hash_id).hashtype.to_s

  unless File.zero?(crack_file)
    File.open(crack_file).each_line do |line|
      hash_pass = line.split(/:/)
      plaintext = hash_pass[-1] # Get last entry
      plaintext = plaintext.chomp
      plaintext = plaintext.scan(/../).map { |x| x.hex.chr}.join # Convert from hex to ascii

      hash_pass.pop # removes tail entry which should have been the plaintext (in hex)
      # Handle salted hashes
      # There's gotta be a better way to do this
      if hashtype == '10' or hashtype == '20' or hashtype == '30' or hashtype == '40' or hashtype == '50' or hashtype == '60' or hashtype == '110' or hashtype == '120' or hashtype == '130' or hashtype == '140' or hashtype == '150' or hashtype == '160' or hashtype == '1100' or hashtype == '1410' or hashtype == '1420' or hashtype == '1430' or hashtype == '1440' or hashtype == '1450' or hashtype == '1460' or hashtype == '2611' or hashtype == '2711' or hashtype == '3610' or hashtype == '3710' or hashtype == '3720' or hashtype == '3910' or hashtype == '4010' or hashtype == '4110' or hashtype == '2711' or hashtype == '11000'
        #hash = hash_pass[0].to_s + ':' + hash_pass[1].to_s
        hash = hash_pass.join(":")
      elsif hashtype == '5500'
        hash = hash_pass[3] + ':' + hash_pass[4] + ':' + hash_pass[5]
      elsif hashtype == '5600'
        hash = hash_pass[0] + ':' + hash_pass[1] + ':' + hash_pass[2] + ':' + hash_pass[3] + ':' + hash_pass[4] + ':' + hash_pass[5]
      elsif hashtype == '7400'
        parts = hash_pass[0].split('$')
        hash = '%' + parts[2].to_s + '$' + parts[3].to_s 
      else
        hash = hash_pass[0]
      end
      p 'job.hashfile_id: ' + job.hashfile_id.to_s
      p 'hashfilehash.hash_id: ' + hashfilehash.to_s
      p 'hashtype: ' + hashtype.to_s
      p 'PLAINTEXT: ' + plaintext.to_s
      p 'Hash: ' + hash.to_s

      # This will pull all hashes from DB regardless of job id
      if hashtype == '7400'
        results = repository(:default).adapter.select('SELECT * FROM hashes WHERE (hashtype = 7400 AND originalhash like ?)', hash)[0]
        records = Hashes.all(fields: [:id, :cracked, :plaintext, :lastupdated], id: results.id)
      else
        records = Hashes.all(fields: [:id, :cracked, :plaintext, :lastupdated], originalhash: hash, cracked: 0 )
      end
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

  # commenting this out now that we are chunking
  #updateJobTaskStatus(id, 'Completed')
  # TODO this might be broken now that we are chunking
  updateDbRunTime(id, job.hashfile_id, run_time)
end
