# this is a test job, you can crib from this module
#
module WordlistChecksum
  @queue = :management
  def self.perform()
    puts '============== generating wordlist checksum ========================'
    # Identify all wordlists without checksums
    @wordlist = Wordlists.all(checksum: nil)
    @wordlist.each do |wl|
      # generate checksum
      puts 'generating checksum for: ' +  wl.path.to_s
      checksum = Digest::SHA2.hexdigest(File.read(wl.path))

      # save checksum to database
      wl.checksum = checksum
      wl.save
    end

  end
end
