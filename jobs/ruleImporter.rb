module RuleImporter
  @queue = :management

  def self.perform()
    sleep(rand(10))
    if ENV['RACK_ENV'] == 'development'
      puts 'Rule fil Importer Class'
    end

    # Identify all rules in directory
    @files = Dir.glob(File.join('control/rules/', '*.rule'))
    @files.each do |path_file|
      rule_entry = Rules.first(path: path_file)
      unless rule_entry
        # Get Name
        name = path_file.split('/')[-1]

        puts 'Importing new Rule file "' + name + '" into HashView.'

        # Adding to DB
        rule_file = Rules.new
        rule_file.lastupdated = Time.now()
        rule_file.name = name
        rule_file.path = path_file
        rule_file.size = 0
        rule_file.checksum = ''
        rule_file.save

      end
    end

    @files = Dir.glob(File.join('control/rules/', '*.rule'))
    @files.each do |path_file|
      rule_file = Rules.first(path: path_file)
      id = rule_file.id
      if rule_file.size == '0'
        size = File.foreach(path_file).inject(0) { |c| c + 1}
        rule_file.size = size
        rule_file.save
      end
      Resque.enqueue(FileChecksum('rules', id))
    end

    if ENV['RACK_ENV'] == 'development'
      puts 'Rule file Importer Class() - done'
    end
  end
end
