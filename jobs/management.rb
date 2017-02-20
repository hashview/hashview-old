class Manager
  @queue = :management

  def self.perform()
    p 'Manager Class'
    while(1)
      # Start Magic Wordlist
      # TODO move this into a resque-scheduler job (see config/resque_schedule.yml)
      Resque.enqueue(MagicWordlist)

      sleep(10)
    end
    p 'Manager Class - Done.. but why?'
  end
end
