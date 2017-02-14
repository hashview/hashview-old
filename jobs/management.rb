class Manager
  @queue = :management

  def self.perform()
    p 'Manager Class'
    while(1)
      # Start Wordlist Importer
      Resque.enqueue(WordlistImporter)

      # Start Magic Wordlist
      Resque.enqueue(MagicWordlist)

      sleep(10)
    end
    p 'Manager Class - Done.. but why?'
  end
end
