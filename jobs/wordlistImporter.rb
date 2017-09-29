module WordlistImporter
  @queue = :management

  def self.perform()
    sleep(rand(10))
    # Setup Logger
    logger_wordlistimporter = Logger.new('logs/jobs/wordlistImporter.log', 'daily')
    if ENV['RACK_ENV'] == 'development'
      logger_wordlistimporter.level = Logger::DEBUG
    else
      logger_wordlistimporter.level = Logger::INFO
    end

    logger_wordlistimporter.debug('Wordlist Importer Class() - has started')

    # Identify all wordlists in directory
    @files = Dir.glob(File.join('control/wordlists/', '*'))
    @files.each do |path_file|
      wordlist_entry = Wordlists.first(path: path_file)
      unless wordlist_entry
        # Get Name
        name = path_file.split('/')[-1]

        # Make sure we're not dealing with a tar, gz, tgz, etc. Not 100% accurate!
        unless name.match(/\.tar|\.7z|\.gz|\.tgz|\.checksum/)
          logger_wordlistimporter.info('Importing new wordslist "' + name + '" into HashView.')

          # Adding to DB
          wordlist = Wordlists.new
          wordlist.lastupdated = Time.now
          wordlist.type = 'static'
          wordlist.name = name
          wordlist.path = path_file
          wordlist.size = 0
          wordlist.checksum = nil
          wordlist.save
        end
      end
    end

    @files = Dir.glob(File.join('control/wordlists/', "*"))
    @files.each do |path_file|
      # Get Name
      name = path_file.split('/')[-1]
      unless name.match(/\.tar|\.7z|\.gz|\.tgz|\.checksum/)
        wordlist = Wordlists.first(path: path_file)
        if wordlist.size == '0'
          size = File.foreach(path_file).inject(0) do |c|
            c + 1
          end
          wordlist.size = size
          wordlist.save
        end
      end
    end

    # after importing all wordlists, generate checksums for each
    # this checksum is used to compare differences with agents
    Resque.enqueue(WordlistChecksum)

    logger_wordlistimporter.debug('Wordlist Importer Class() - has completed')
  end
end
