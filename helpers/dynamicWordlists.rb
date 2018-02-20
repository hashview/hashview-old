def updateDynamicWordlist(wordlist_id)

  wordlist = Wordlists.first(id: wordlist_id)
  file = wordlist.path

  if wordlist.scope == 'all'
    @results = HVDB.fetch('SELECT plaintext FROM hashes WHERE cracked = 1')
  elsif wordlist.scope == 'customer'
    customer = Customers.first(wl_id: wordlist_id)
    @results = HVDB.fetch('SELECT h.plaintext FROM hashes h LEFT JOIN hashfilehashes a on h.id = a.hash_id LEFT JOIN hashfiles f on a.hashfile_id = f.id WHERE (f.customer_id = ? AND h.cracked = 1)', customer[:id])
  elsif wordlist.scope == 'hashfile'
    hashfile = Hashfiles.first(wl_id: wordlist_id)
    @results = HVDB.fetch('SELECT h.plaintext FROM hashes h LEFT JOIN hashfilehashes a ON h.id = a.hash_id LEFT JOIN hashfiles f on a.hashfile_id = f.id WHERE (a.hashfile_id = ? and h.cracked = 1)', hashfile[:id])
  end

  # if file is not there, create it
  unless File.file?(file)
    handler = File.open(file, 'w')
    handler.close
  end

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