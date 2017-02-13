module WordlistImporter 
  @queue = :management

  def self.perform()
    puts 'Wordlist Importer class'

    # Identify all wordlists in directory
    @files = Dir.glob(File.join('control/wordlists/', "*")) 
    @files.each do |path_file|
      wordlist_entry = Wordlists.first(path: path_file)
      if wordlist_entry
        puts "IN DB: " + wordlist_entry.path.to_s
      else
        puts "NOT IN DB: " + path_file.to_s

        # Get Name
        name = path_file.split('/')[-1]

        # Make sure we're not dealing with a tar, gz, tgz, etc. Not 100% accurate!
        unless name.match(/\.tar|\.7z|\.gz|\.tgz/)

          puts "Importing " + name
          # Finding Size
          size = File.foreach(path_file).inject(0) { |c| c + 1 }

          # Adding to DB
          wordlist = Wordlists.new
          wordlist.lastupdated = Time.now()
          wordlist.name = name
          wordlist.path = path_file
          wordlist.size = size
          wordlist.save
        end
      end
    end
  end
end
