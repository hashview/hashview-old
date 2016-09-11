require 'resque/tasks'
require './jobs/jobq.rb'
require 'rake/testtask'
require 'data_mapper'

Rake::TestTask.new do |t|
  #ENV['RACK_ENV'] = 'test'
  t.pattern = "tests/*_spec.rb"
  t.verbose
end

desc "Setup test database"
namespace :db do
  task :create do
    if ENV['RACK_ENV'].nil?
      ENV['RACK_ENV'] = 'development'
    end
    puts "setting up database for environment: #{ENV['RACK_ENV']}"
    #ENV['RACK_ENV'] = 'test'
    config = YAML.load_file('config/database.yml')
    config = config[ENV['RACK_ENV']]
    user, password, host = config['user'], config['password'], config['hostname']
    database = config['database']
    charset = config['charset']   || ENV['CHARSET']   || 'utf8'
    collation = config['collation'] || ENV['COLLATION'] || 'utf8_unicode_ci'

    # create database in mysql for datamapper
    query = [
      "mysql", "--user=#{user}", "--password=#{password}", "--host=#{host} -e", "CREATE DATABASE #{database} DEFAULT CHARACTER SET #{charset} DEFAULT COLLATE #{collation}".inspect
    ]
    begin
      system(query.compact.join(" "))
      #require_relative 'model/master.rb'
    rescue
      raise "Something went wrong. double check your config/database.yml file and manually test access to mysql."
    end
  end

  task :destroy do
    if ENV['RACK_ENV'].nil?
      ENV['RACK_ENV'] = 'development'
    end
    puts "destroying database for environment: #{ENV['RACK_ENV']}"
    #ENV['RACK_ENV'] = 'test'
    config = YAML.load_file('config/database.yml')
    config = config[ENV['RACK_ENV']]
    user, password, host = config['user'], config['password'], config['hostname']
    database = config['database']
    charset = config['charset']   || ENV['CHARSET']   || 'utf8'
    collation = config['collation'] || ENV['COLLATION'] || 'utf8_unicode_ci'

    # create database in mysql for datamapper
    query = [
      "mysql", "--user=#{user}", "--password=#{password}", "--host=#{host} -e", "DROP DATABASE #{database}".inspect
    ]
    begin
      system(query.compact.join(" "))
      #require_relative 'model/master.rb'
    rescue
      raise "Something went wrong. double check your config/database.yml file and manually test access to mysql."
    end
  end

  namespace :auto do
    desc "Perform auto migration (reset your db data)"
    task :migrate do
      if ENV['RACK_ENV'].nil?
        ENV['RACK_ENV'] = 'development'
      end
      require_relative 'model/master.rb'
      DataMapper.repository.auto_upgrade!
      puts "db:auto:migrate executed"
    end

    desc "Perform non destructive auto migration"
    task :upgrade do
      if ENV['RACK_ENV'].nil?
        ENV['RACK_ENV'] = 'development'
      end
      DataMapper.repository.auto_upgrade!
      puts "db:auto:upgrade executed"
    end
  end

end
