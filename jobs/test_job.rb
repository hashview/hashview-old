# this is a test job, you can crib from this module
#
module TestJob
  @queue = :management
  def self.perform()
    puts "============== this is a test job ========================"
  end
end