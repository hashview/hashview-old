module WordlistImporter 
  @queue = :management

  def self.perform()
    if ENV['RACK_ENV'] == 'development'
      puts 'Wordlist Importer Class'
    end

    # Identify all wordlists in directory
    @files = Dir.glob(File.join('control/wordlists/', "*")) 
    @files.each do |path_file|
      wordlist_entry = Wordlists.first(path: path_file)
      unless wordlist_entry
        # Get Name
        name = path_file.split('/')[-1]

        # Make sure we're not dealing with a tar, gz, tgz, etc. Not 100% accurate!
        unless name.match(/\.tar|\.7z|\.gz|\.tgz|\.checksum/)

          puts 'Importing new wordslist "' + name + '" into HashView.'
          # Finding Size
          size = File.foreach(path_file).inject(0) { |c| c + 1 }

          # Adding to DB
          wordlist = Wordlists.new
          wordlist.lastupdated = Time.now()
          wordlist.name = name
          wordlist.path = path_file
          #wordlist.size = size
          wordlist.checksum = ''
          wordlist.save

          #Resque.enqueue(MagicWordlist)
        end
      end
    end

    # after importing all wordlists, generate checksums for each
    # this checksum is used to compare differences with agents
    Resque.enqueue(WordlistChecksum)

    if ENV['RACK_ENV'] == 'development'
      puts 'Wordlist Importer Class() - done'
    end
  end
end
