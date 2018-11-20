module RuleImporter
  @queue = :management

  def self.perform()
    sleep(rand(10))
    require_relative '../models/master'
    logger_ruleimporter = Logger.new('logs/jobs/ruleImporter.log', 'daily')
    if ENV['RACK_ENV'] == 'development'
      logger_ruleimporter.level = Logger::DEBUG
    else
      logger_ruleimporter.level = Logger::INFO
    end

    logger_ruleimporter.debug('Rule Importer Class() - has started')

    # Identify all rules in directory
    @files = Dir.glob(File.join('control/rules/', '*.rule'))
    @files.each do |path_file|
      rule_entry = Rules.first(path: path_file)
      unless rule_entry
        # Get Name
        name = path_file.split('/')[-1]
        logger_ruleimporter.info('Importing new Rule ""' + name + '"" into HashView.')

        # Adding to DB
        rule_file = Rules.new
        rule_file.lastupdated = Time.now
        rule_file.name = name
        rule_file.path = path_file
        rule_file.size = 0
        rule_file.checksum = Digest::SHA256.file(path_file).hexdigest
        rule_file.save

      end
    end

    @files = Dir.glob(File.join('control/rules/', '*.rule'))
    @files.each do |path_file|
      rule_file = Rules.first(path: path_file)
      if rule_file.size == '0'
        size = File.foreach(path_file).inject(0) do |c|
          c + 1
        end
        rule_file.size = size
        rule_file.save
      end
    end

    logger_ruleimporter.debug('Rule Importer Class() - has completed')
  end
end
