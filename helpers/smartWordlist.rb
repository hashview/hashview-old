def updateSmartWordlist

  # Set all jobqueue items that are 'queued' to 'paused'
  taskqueues = Taskqueues.where(status: 'Queued').all
  taskqueues.each do |entry|
    entry.status = 'Paused'
    entry.save
  end

  wordlist = Wordlists.first(name: 'Smart Wordlist')
  # Create Smart word list if one doesn't exists
  if wordlist.nil?
    wordlist = Wordlists.new
    wordlist.lastupdated = Time.now
    wordlist.type = 'dynamic'
    wordlist.name = 'Smart Wordlist'
    wordlist.path = 'control/wordlists/SmartWordlist.txt'
    wordlist.size = '0'
    wordlist.checksum = nil
    wordlist.save
    system('touch control/wordlists/SmartWordlist.txt')
  end

  # Get list of all plaintext passwords and save it to a file
  @customers = Customers.order(Sequel.asc(:name)).all
  @plaintexts = Hashes.where(cracked: 1, unique: true).order(Sequel.asc(:plaintext)).select(:plaintext).all
  file_name = 'control/tmp/plaintext.txt'

  File.open(file_name, 'w') do |f|
    @plaintexts.each do |entry|
      f.puts entry.plaintext
    end
  end

  # Get list of all wordlists
  # TODO add --parallel #
  # We could get this via the facter gem
  # Facter.value('processors'['count'])
  cpu_count = `cat /proc/cpuinfo | grep processor | wc -l`.to_i
  shell_cmd = 'sort --parallel ' + cpu_count.to_s + ' -u control/tmp/plaintext.txt '
  @wordlists = Wordlists.all
  @wordlists.each do |entry|
    shell_cmd = shell_cmd + entry.path.to_s + ' ' if entry.type == 'static'
  end
  # We move to temp to prevent wordlist importer from accidentally loading the smart wordlist too early
  shell_cmd += '-o control/tmp/SmartWordlist.txt'
  p 'shell_cmd: ' + shell_cmd
  system(shell_cmd)

  shell_mv_cmd = 'mv control/tmp/SmartWordlist.txt control/wordlists/SmartWordlist.txt'
  system(shell_mv_cmd)

  # update wordlist size
  wordlist = Wordlists.first(name: 'Smart Wordlist')
  wordlist.size = '0' # trigger background job
  # update hashvalue
  wordlist.checksum = nil
  wordlist.save

  # Update checksum
  Resque.enqueue(WordlistChecksum)

  # Remove plaintext list
  File.delete('control/tmp/plaintext.txt') if File.exist?('control/tmp/plaintext.txt')

  # Update keyspace per task ( really should be done at runtime)
  tasks = Tasks.where(wl_id: wordlist.id).all
  tasks.each do |task|
    task.keyspace = getKeyspace(task)
    task.save
  end

  # resume all jobqueue items that are 'paused' to 'queued'
  taskqueues = Taskqueues.where(status: 'Paused').all
  taskqueues.each do |entry|
    entry.status = 'Queued'
    entry.save
  end
end
