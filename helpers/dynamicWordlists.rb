def updateDynamicWordlist(wordlist_id)
  wordlist = Wordlists.first(id: wordlist_id)
  file = wordlist.path

  hashfile = Hashfiles.first(wl_id: wordlist_id)
  return true if hashfile.nil? # Should we return an error instead?

  # if file is not there, create it
  unless File.file?(file)
    handler = File.open(file, 'w')
    handler.close
  end

  @results = HVDB.fetch('SELECT h.plaintext FROM hashes h LEFT JOIN hashfilehashes a ON h.id = a.hash_id LEFT JOIN hashfiles f on a.hashfile_id = f.id WHERE (a.hashfile_id = ? and h.cracked = 1)', hashfile[:id])

  File.open(file, 'w') do |f|
    @results.each do |entry|
      f.puts entry['plaintext']
    end
  end
  wordlist.checksum = Digest::SHA2.hexdigest(File.read(file))
  size = File.foreach(file).inject(0) do |c|
    c + 1
  end
  wordlist.size = size
  wordlist.save
  true

end
