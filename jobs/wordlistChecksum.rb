# this job generates checksums for each wordlist
#
module WordlistChecksum
  @queue = :management
  def self.perform()
    require_relative '../models/master'
    # Setup Logger
    logger_wordlistchecksum = Logger.new('logs/jobs/wordlistchecksum.log', 'daily')
    if ENV['RACK_ENV'] == 'development'
      logger_wordlistchecksum.level = Logger::DEBUG
    else
      logger_wordlistchecksum.level = Logger::INFO
    end

    logger_wordlistchecksum.debug('Wordlist Checksum Class() - has started')

    # Identify all wordlists without checksums
    @wordlist = Wordlists.where(checksum: nil).all
    @wordlist.each do |wl|
      # generate checksum
      logger_wordlistchecksum.info('generating checksum for: ' + wl.path.to_s)
      checksum = Digest::SHA256.file(wl.path).hexdigest

      # save checksum to database
      wl.checksum = checksum
      wl.save
    end

    logger_wordlistchecksum.debug('Wordlist Checksum Class() - has completed')
  end
end
