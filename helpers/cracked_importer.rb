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

  jobtasks = Jobtasks.first(id: id)
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
      if hashtype == '10' || hashtype == '20' || hashtype == '30' || hashtype == '40' || hashtype == '50' || hashtype == '60' ||hashtype == '110' || hashtype == '120' || hashtype == '121' || hashtype == '130' || hashtype == '140' || hashtype == '150' || hashtype == '160' || hashtype == '1100' || hashtype == '1410' || hashtype == '1420' || hashtype == '1430' || hashtype == '1440' || hashtype == '1450' || hashtype == '1460' || hashtype == '2611' || hashtype == '2711' || hashtype == '3610' || hashtype == '3710' || hashtype == '3720' || hashtype == '3910' || hashtype == '4010' || hashtype == '4110' || hashtype == '2711' || hashtype == '11000'
        hash = hash_pass.join(":")
      elsif hashtype == '5500'
        hash = hash_pass[3] + ':' + hash_pass[4] + ':' + hash_pass[5]
      elsif hashtype == '5600'
        hash = hash_pass[0] + ':' + hash_pass[1] + ':' + hash_pass[2] + ':' + hash_pass[3] + ':' + hash_pass[4] + ':' + hash_pass[5]
      elsif hashtype == '7400'
        parts = hash_pass[0].split('$')
        # p 'PARTS: ' + parts.to_s
        hash = '%' + parts[3].to_s + '$' + parts[4].to_s
      else
        hash = hash_pass[0]
      end

      # This will pull all hashes from DB regardless of job id
      if hashtype == '7400'
        results = repository(:default).adapter.select('SELECT * FROM hashes WHERE (hashtype = 7400 AND originalhash like ?)', hash)[0]
        records = Hashes.all(fields: [:id, :cracked, :plaintext, :lastupdated], id: results.id)
      else
        records = Hashes.all(fields: [:id, :cracked, :plaintext, :lastupdated], originalhash: hash, cracked: 0)
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
    p 'ERROR: ' + $!.to_s
  end

  # TODO this might be broken now that we are chunking
  updateDbRunTime(id, job.hashfile_id, run_time)
end
