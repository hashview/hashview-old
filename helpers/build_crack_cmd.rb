helpers do
  # this function builds the main hashcat cmd we use to crack. this should be moved to a helper script soon
  def buildCrackCmd(job_id, task_id)
    # order of opterations -m hashtype -a attackmode is dictionary? set wordlist, set rules if exist file/hash
    hc_settings = HashcatSettings.first
    hc_binpath = hc_settings.hc_binpath
    max_task_time = hc_settings.max_task_time
    @task = Tasks.first(id: task_id)
    @job = Jobs.first(id: job_id)
    hashfile_id = @job.hashfile_id
    hash_id = Hashfilehashes.first(hashfile_id: hashfile_id).hash_id
    hashtype = Hashes.first(id: hash_id).hashtype.to_s
  
    attackmode = @task.hc_attackmode.to_s
    mask = @task.hc_mask

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
    # elvated permissions and we wont be able to read it
    crack_file = 'control/outfiles/hc_cracked_' + @job.id.to_s + '_' + @task.id.to_s + '.txt'
    File.open(crack_file, 'w')

    if attackmode == 'bruteforce'
      cmd = hc_binpath + ' -m ' + hashtype + ' --potfile-disable' + ' --status --status-timer=15' + ' --runtime=' + max_task_time + ' --outfile-format 5 ' + ' --outfile ' + crack_file + ' ' + ' -a 3 ' + target_file
    elsif attackmode == 'maskmode'
      cmd = hc_binpath + ' -m ' + hashtype + ' --potfile-disable' + ' --status --status-timer=15' + ' --outfile-format 5 ' + ' --outfile ' + crack_file + ' ' + ' -a 3 ' + target_file + ' ' + mask
    elsif attackmode == 'dictionary'
      if @task.hc_rule == 'none'
        cmd = hc_binpath + ' -m ' + hashtype + ' --potfile-disable' + ' --status --status-timer=15' + ' --outfile-format 5 ' + ' --outfile ' + crack_file + ' ' + target_file + ' ' + wordlist.path
      else
        cmd = hc_binpath + ' -m ' + hashtype + ' --potfile-disable' + ' --status --status-timer=15' + ' --outfile-format 5 ' + ' --outfile ' + crack_file + ' ' + ' -r ' + 'control/rules/' + @task.hc_rule + ' ' + target_file + ' ' + wordlist.path
      end
    elsif attackmode == 'combinator'
      cmd = hc_binpath + ' -m ' + hashtype + ' --potfile-disable' + ' --status --status-timer=15' + ' --outfile-format 5 ' + ' --outfile ' + crack_file + ' ' + ' -a 1 ' + target_file + ' ' + wordlist_one.path + ' ' + ' ' + wordlist_two.path + ' ' + @task.hc_rule.to_s
    end

    # Add global options
    # --opencl-device-types
    if hc_settings.opencl_device_types.to_s != '0'
      cmd = cmd + ' --opencl-device-types ' + hc_settings.opencl_device_types.to_s
    end

    # --workload-profile
    if hc_settings.workload_profile.to_s != '0'
      cmd = cmd + ' --workload-profile ' + hc_settings.workload_profile.to_s
    end

    # --gpu-temp-disable
    if hc_settings.gpu_temp_disable == true
      cmd = cmd + ' --gpu-temp-disable'
    end

    # --gpu-temp-abort
    if hc_settings.gpu_temp_abort.to_s != '0'
      cmd = cmd + ' --gpu-temp-abort=' + hc_settings.gpu_temp_abort.to_s
    end

    # --gpu-temp-retain
    if hc_settings.gpu_temp_retain.to_s != '0'
      cmd = cmd + ' --gpu-temp-retain=' + hc_settings.gpu_temp_retain.to_s
    end

    # --force
    if hc_settings.hc_force == true
      cmd = cmd + ' --force'
    end

    p cmd
    cmd
  end
end
