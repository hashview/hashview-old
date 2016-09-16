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

  task :provision_defaults do
    config = YAML.load_file('config/database.yml')
    config = config[ENV['RACK_ENV']]
    user, password, host = config['user'], config['password'], config['hostname']
    database = config['database']

    puts '[*] Setting up default settings ...'
    # Create Default Settings
    query = [
      "mysql", "--user=#{user}", "--password=#{password}", "--host=#{host}", "--database=#{database}", "-e INSERT INTO settings (maxtasktime) VALUES ('86400')".inspect
    ]
    begin
      system(query.compact.join(" "))
    rescue
      raise "Error in creating default settings"
    end


    puts '[*] Setting up default customer ...'
    # Create Default customer
    query = [
      "mysql", "--user=#{user}", "--password=#{password}", "--host=#{host}", "--database=#{database}", "-e INSERT INTO customers (name, description) VALUES ('test', 'test')".inspect
    ]
    begin
      system(query.compact.join(" "))
    rescue
      raise "Error in creating default customer"
    end

    system('gunzip -k control/wordlists/password.gz')
    puts '[*] Settings up default wordlist ...'
    # Create Default Wordlist
    query = [
      "mysql", "--user=#{user}", "--password=#{password}", "--host=#{host}", "--database=#{database}", "-e INSERT INTO wordlists (name, path, size) VALUES ('DEFAULT WORDLIST', 'control/wordlists/password', '3546')".inspect
    ]
    begin
      system(query.compact.join(" "))
    rescue
      raise "Error in creating default wordlist"
    end

    # Create Default Task Dictionary
    puts '[*] Setting up default dictionary'
    query = [
      "mysql", "--user=#{user}", "--password=#{password}", "--host=#{host}", "--database=#{database}", "-e INSERT INTO tasks (name, wl_id, hc_attackmode, hc_rule) VALUES ('Basic Dictionary', '1', 'dictionary', 'none')".inspect
    ]
    begin
      system(query.compact.join(" "))
    rescue
      raise "Error in creating default dictionary task"
    end

    # Create Default Dictionary + Rule Task 
    puts '[*] Setting up default dictionary + rule task'
    query = [
      "mysql", "--user=#{user}", "--password=#{password}", "--host=#{host}", "--database=#{database}", "-e INSERT INTO tasks (name, wl_id, hc_attackmode, hc_rule) VALUES ('Basic Dictionary + Best64 Rules', '1', 'dictionary', 'best64.rule')".inspect
    ]
    begin
      system(query.compact.join(" "))
    rescue
      raise "Error in creating default dictionary task + rule"
    end

    # Create Default Mask task 
    puts '[*] Setting up default mask task'
    query = [
      "mysql", "--user=#{user}", "--password=#{password}", "--host=#{host}", "--database=#{database}", "-e INSERT INTO tasks (name, hc_attackmode, hc_mask) VALUES ('Lower Alpha 7char', 'maskmode', '?l?l?l?l?l?l?l')".inspect
    ]
    begin
      system(query.compact.join(" "))
    rescue
      raise "Error in creating default mask task"
    end

    # Create Default Raw Brute
    puts '[*] Setting up default bute task'
    query = [
      "mysql", "--user=#{user}", "--password=#{password}", "--host=#{host}", "--database=#{database}", "-e INSERT INTO tasks (name, hc_attackmode) VALUES ('Raw Brute', 'bruteforce')".inspect
    ]
    begin
      system(query.compact.join(" "))
    rescue
      raise "Error in creating default bute task"
    end



  end

  namespace :auto do
    desc "Perform auto migration (reset your db data)"
    task :migrate do
      if ENV['RACK_ENV'].nil?
        ENV['RACK_ENV'] = 'development'
      end
      require_relative 'model/master.rb'
      DataMapper.finalize
      DataMapper.auto_upgrade!
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
