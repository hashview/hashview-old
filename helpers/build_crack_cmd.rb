helpers do
  # this function builds the main hashcat cmd we use to crack. this should be moved to a helper script soon
  def buildCrackCmd(job_id, task_id)
    p 'BUILD CRACK CMD: ' + job_id.to_s + ' ' + task_id.to_s

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

    # Add Session
    session = rand(36**8).to_s(36)[0..3]

    case attackmode
    when 'bruteforce'
      cmd = hc_binpath + ' --session ' + session.to_s + ' -m ' + hashtype + ' --potfile-disable' + ' --status --status-timer=15' + ' --runtime=' + max_task_time + ' --outfile-format 5 ' + ' --outfile ' + crack_file + ' ' + ' -a 3 ' + target_file
    when 'maskmode'
      cmd = hc_binpath + ' --session ' + session.to_s + ' -m ' + hashtype + ' --potfile-disable' + ' --status --status-timer=15' + ' --outfile-format 5 ' + ' --outfile ' + crack_file + ' ' + ' -a 3 ' + target_file + ' ' + mask
    when 'dictionary'
      if @task.hc_rule.nil? || @task.hc_rule == 'none'
        cmd = hc_binpath + ' --session ' + session.to_s + ' -m ' + hashtype + ' --potfile-disable' + ' --status --status-timer=15' + ' --outfile-format 5 ' + ' --outfile ' + crack_file + ' ' + target_file + ' ' + wordlist.path
      else
        cmd = hc_binpath + ' --session ' + session.to_s + ' -m ' + hashtype + ' --potfile-disable' + ' --status --status-timer=15' + ' --outfile-format 5 ' + ' --outfile ' + crack_file + ' ' + ' -r ' + rules_file.path + ' ' + target_file + ' ' + wordlist.path
      end
    when 'combinator'
      cmd = hc_binpath + ' --session ' + session.to_s + ' -m ' + hashtype + ' --potfile-disable' + ' --status --status-timer=15' + ' --outfile-format 5 ' + ' --outfile ' + crack_file + ' ' + ' -a 1 ' + target_file + ' ' + wordlist_one.path + ' ' + ' ' + wordlist_two.path + ' ' + @task.hc_rule.to_s
    else
      puts 'INVALID ATTACK MODE: ' + attackmode.to_s
    end

    # Add global options
    # --opencl-device-types
    cmd += ' --opencl-device-types ' + hc_settings.opencl_device_types.to_s if hc_settings.opencl_device_types.to_s != '0'

    # --workload-profile
    cmd += ' --workload-profile ' + hc_settings.workload_profile.to_s if hc_settings.workload_profile.to_s != '0'

    # --gpu-temp-disable
    cmd += ' --gpu-temp-disable' if hc_settings.gpu_temp_disable

    # --gpu-temp-abort
    cmd += ' --gpu-temp-abort=' + hc_settings.gpu_temp_abort.to_s if hc_settings.gpu_temp_abort.to_s != '0'

    # --gpu-temp-retain
    cmd += ' --gpu-temp-retain=' + hc_settings.gpu_temp_retain.to_s if hc_settings.gpu_temp_retain.to_s != '0'

    # --force
    cmd += ' --force' if hc_settings.hc_force

    cmd += ' -O' if hc_settings.optimized_drivers

    cmd
  end
end
