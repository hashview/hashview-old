require 'resque/tasks'
require './jobs/jobq.rb'
require 'rake/testtask'

Dir.glob('jobs/*.rake').each { |r| load r }

Rake::TestTask.new do |t|
  ENV['RACK_ENV'] = 'test'
  t.pattern = "tests/*_spec.rb"
  t.verbose
end
