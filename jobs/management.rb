class Manager
  @queue = :management

  def self.perform()
    p 'Manager Class'
    while(1)
      # Start Wordlist Importer
      Resque.enqueue(WordlistImporter)

      # Start Magic Wordlist
      Resque.enqueue(MagicWordlist)

      sleep(60)
    end
  end
end
