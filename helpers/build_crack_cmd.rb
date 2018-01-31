helpers do
  # this function builds the main hashcat cmd we use to crack. this should be moved to a helper script soon
  def buildCrackCmd(job_id, task_id)
    cmds = []

    chunk_size = Settings.first().chunk_size
    chunks = {}
    chunk_skip = 0

    # order of opterations -m hashtype -a attackmode is dictionary? set wordlist, set rules if exist file/hash
    hc_settings = HashcatSettings.first
    # we no loger pull hc_binpath from the db. set this to a placeholder value and each
    # agent will replace it with their local hc_binpath
    hc_binpath = '@HASHCATBINPATH@'
    max_task_time = hc_settings.max_task_time
    @task = Tasks.first(id: task_id)
    @job = Jobs.first(id: job_id)
    rules_file = Rules.first(id: @task.hc_rule)
    hashfile_id = @job.hashfile_id
    hash_id = Hashfilehashes.first(hashfile_id: hashfile_id).hash_id
    hashtype = Hashes.first(id: hash_id).hashtype.to_s

    attackmode = @task.hc_attackmode.to_s
    mask = @task.hc_mask

    # if task contains a keyspace that is gt 0 perform chunking
    if @task[:keyspace].nil?
      chunking = false
    elsif @task[:keyspace].to_i > 0 && @task[:keyspace].to_i > chunk_size
      chunking = true

      # build a hash containing our skip and limit values
      chunk_num = 0
      while chunk_skip < @task[:keyspace].to_i
        skip = chunk_skip

        chunks[chunk_num] = [skip, chunk_size]

        chunk_num += 1
        chunk_skip = skip + chunk_size
      end
    end

    if attackmode == 'combinator'
      wordlist_list = @task.wl_id
      @wordlist_list_elements = wordlist_list.split(',')
      wordlist_one = Wordlists.first(id: @wordlist_list_elements[0])
      wordlist_two = Wordlists.first(id: @wordlist_list_elements[1])
    else
      wordlist = Wordlists.first(id: @task.wl_id)
    end

    target_file = 'control/hashes/hashfile_' + job_id.to_s + '_' + task_id.to_s + '.txt'

    # we assign and write output file before hashcat.
    # if hashcat creates its own output it does so with
    # elevated permissions and we wont be able to read it
    crack_file = 'control/outfiles/hc_cracked_' + @job.id.to_s + '_' + @task.id.to_s + '.txt'
    File.open(crack_file, 'w')

    case attackmode
    when 'bruteforce'
      cmd = hc_binpath + ' -m ' + hashtype + ' --potfile-disable' + ' --status --status-timer=15' + ' --runtime=' + max_task_time + ' --outfile-format 5 ' + ' --outfile ' + crack_file + ' ' + ' -a 3 ' + target_file
    when 'maskmode'
      cmd = hc_binpath + ' -m ' + hashtype + ' --potfile-disable' + ' --status --status-timer=15' + ' --outfile-format 5 ' + ' --outfile ' + crack_file + ' ' + ' -a 3 ' + target_file + ' ' + mask
    when 'dictionary'
      if @task.hc_rule.nil? || @task.hc_rule == 'none'
        cmd = hc_binpath + ' -m ' + hashtype + ' --potfile-disable' + ' --status --status-timer=15' + ' --outfile-format 5 ' + ' --outfile ' + crack_file + ' ' + target_file + ' ' + wordlist.path
      else
        cmd = hc_binpath + ' -m ' + hashtype + ' --potfile-disable' + ' --status --status-timer=15' + ' --outfile-format 5 ' + ' --outfile ' + crack_file + ' ' + ' -r ' + rules_file.path + ' ' + target_file + ' ' + wordlist.path
      end
    when 'combinator'
      cmd = hc_binpath + ' -m ' + hashtype + ' --potfile-disable' + ' --status --status-timer=15' + ' --outfile-format 5 ' + ' --outfile ' + crack_file + ' ' + ' -a 1 ' + target_file + ' ' + wordlist_one.path + ' ' + ' ' + wordlist_two.path + ' ' + @task.hc_rule.to_s
    else
      puts 'INVALID ATTACK MODE: ' + attackmode.to_s
    end

    # Add global options
    # --opencl-device-types
    if hc_settings.opencl_device_types.to_s != '0'
      cmd += ' --opencl-device-types ' + hc_settings.opencl_device_types.to_s
    end

    # --workload-profile
    if hc_settings.workload_profile.to_s != '0'
      cmd += ' --workload-profile ' + hc_settings.workload_profile.to_s
    end

    # --gpu-temp-disable
    if hc_settings.gpu_temp_disable == true
      cmd += ' --gpu-temp-disable'
    end

    # --gpu-temp-abort
    if hc_settings.gpu_temp_abort.to_s != '0'
      cmd += ' --gpu-temp-abort=' + hc_settings.gpu_temp_abort.to_s
    end

    # --gpu-temp-retain
    if hc_settings.gpu_temp_retain.to_s != '0'
      cmd += ' --gpu-temp-retain=' + hc_settings.gpu_temp_retain.to_s
    end

    # --force
    if hc_settings.hc_force == true
      cmd += ' --force'
    end

    if hc_settings.optimized_drivers == true
      cmd += ' -O'
    end

    # add skip and limit if we are chunking this task
    if chunking == true
      chunks.each do |_unused, value|
        if attackmode == 'maskmode' || attackmode == 'dictionary'
          cmds << cmd + ' -s ' + value[0].to_s + ' -l ' + value[1].to_s
          p cmd
        end
      end
    else
      cmds << cmd
    end

    cmds
  end
end
