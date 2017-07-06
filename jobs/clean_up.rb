# this is a cleanup job to remove old files
#
require_relative '../helpers/status'

def cleanDir(path)
  @files = Dir.glob(File.join(path))
  @files.each do |path_file|
    if (Time.now - File.ctime(path_file))/(24*3600) > 30 # Need to change to a user defined setting
      if ENV['RACK_ENV'] == 'development'
        puts 'File: ' + path_file.to_s + ' is greater than 30 days old. Deleting'
      end
      File.delete(path_file)
    end
  end
end

module CleanUp
  @queue = :management
  def self.perform()
    if ENV['RACK_ENV'] == 'development'
      p 'CleanUp Class - start'
    end

    # control/tmp/*
    cleanDir('control/tmp/*')

    # control/outfiles/found_*.txt
    cleanDir('control/outfiles/found_*')

    # control/outfiles/left_*.txt
    cleanDir('control/outfiles/left_*')

    # control/hashes/hashfile_upload_*
    cleanDir('hashes/hashfile_upload_*')

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

    if ENV['RACK_ENV'] == 'development'
      p 'CleanUp Class - Done'
    end
  end
end
