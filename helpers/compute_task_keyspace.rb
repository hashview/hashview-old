# this helper generates the keyspace of a given task. Helpful when chunking the task for multiple agents.
def getKeyspace(task)

  # get hashcat binarypath from config
  hashcatbinpath = JSON.parse(File.read('config/agent_config.json'))['hc_binary_path']

  # is task a dictionary attack mode (-a 0)
  if task.hc_attackmode == 'dictionary'
    # TODO: 5/18/17 normally we'd check if it has rules too, but i cant get hashcat to compute keyspace with rules :-(

    # get wordlist path
    wordlist = Wordlists.first(id: task.wl_id)
    wl_path = wordlist.path

    # build hashcat keyspace command
    cmd = hashcatbinpath + ' ' + wl_path + ' --keyspace'

  elsif task.hc_attackmode == 'maskmode'

    # build hashcat keyspace command
    cmd = hashcatbinpath + ' -a 3 ' + task.hc_mask + ' --keyspace'

  elsif task.hc_attackmode == 'bruteforce'

    # do not chunk this task
    return 0

  elsif task.hc_attackmode == 'combinator'

    # get wordlists path. wordlists will be comma split. ex: 1,2
    wl = task.wl_id.split(',')
    wordlist1 = Wordlists.first(id: wl[0])
    wordlist1_path = wordlist1.path
    wordlist2 = Wordlists.first(id: wl[1])
    wordlist2_path = wordlist2.path

    # hashcat keyspace switch cannot compute in this mode. we just add the two keyspaces together
    cmd = hashcatbinpath + ' ' + wordlist1_path + ' --keyspace'
    keyspace2 = `#{cmd}`
    cmd = hashcatbinpath + ' ' + wordlist2_path + ' --keyspace'

  elsif task.hc_attackmode == 'wordmask'
    # get wordlist path
    wordlist = Wordlists.first(id: task.wl_id)
    wl_path = wordlist.path

    # build hashcat keyspace command

    cmd = hashcatbinpath + ' -a 6 ' + wl_path + ' ' + task.hc_mask + ' --keyspace'

  elsif task.hc_attackmode == 'maskword'

    # get wordlist path
    wordlist = Wordlists.first(id: task.wl_id)
    wl_path = wordlist.path

    # build hashcat keyspace command
    cmd = hashcatbinpath + ' -a 7 ' + task.hc_mask + ' ' + wl_path + ' --keyspace'
  end

  # run hashcat keyspace command
  keyspace = `#{cmd}`
  # simple check to make sure we didnt error out. the keyspace switch is a little iffy.
  # note: anything over ?ax10 will throw a integer overflow error in hashcat
  unless keyspace.include?('overflow') || keyspace.include?('Usage')
    if keyspace2
      keyspace = keyspace.to_i + keyspace2.to_i
    end
    return keyspace.to_i
  else
    # zero is used to represent infinity or no chunking
    return 0
  end

end