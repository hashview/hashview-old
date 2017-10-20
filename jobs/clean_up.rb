# this is a cleanup job to remove old files
#
require_relative '../helpers/status'

def cleanDir(path)
  # Setup Logger
  # Not a fan of this, not sure if i can just pass the logger_cleanup object instead?
  logger_cleanup = Logger.new('logs/jobs/cleanup.log', 'daily')
  if ENV['RACK_ENV'] == 'development'
    logger_cleanup.level = Logger::DEBUG
  else
    logger_cleanup.level = Logger::INFO
  end


  @files = Dir.glob(File.join(path))
  @files.each do |path_file|
    if (Time.now - File.ctime(path_file)) / (24 * 3600) > 30 # TODO Need to change to a user defined setting
      logger_cleanup.info('File: ' + path_file.to_s + ' is greater than 30 days old. Deleting')
      File.delete(path_file)
    end
  end
end

module CleanUp
  @queue = :management
  def self.perform()
    # Setup Logger
    logger_cleanup = Logger.new('logs/jobs/cleanup.log', 'daily')
    if ENV['RACK_ENV'] == 'development'
      logger_cleanup.level = Logger::DEBUG
    else
      logger_cleanup.level = Logger::INFO
    end

    logger_cleanup.debug('Cleanup Class() - has started')

    # control/tmp/*
    cleanDir('control/tmp/*')

    # control/outfiles/found_*.txt
    cleanDir('control/outfiles/found_*')

    # control/outfiles/left_*.txt
    cleanDir('control/outfiles/left_*')

    # control/hashes/hashfile_upload_*
    cleanDir('control/hashes/hashfile_upload_*')

    # control/logs/*.log
    cleanDir('control/logs/*.log')

    # control/logs/jobs/*.log
    cleanDir('control/logs/jobs/*.log')

    # TODO
    # Maybe do a better way of validating we're not going to delete an actively used file?
    unless isBusy?
      # control/outfiles/hc_cracked_*
      cleanDir('control/outfiles/hc_cracked_*')

      # control/outfiles/hcoutput_*
      cleanDir('control/outfiles/hcoutput_*')

      # control/hashes/hashfile_*.txt
      cleanDir('control/hashes/hashfile_*.txt')
    end

    logger_cleanup.debug('Cleanup Class() - has completed')
  end
end
