require 'resque/tasks'
require './jobs/jobq.rb'
require 'rake/testtask'
require 'data_mapper'
require 'mysql'

Rake::TestTask.new do |t|
  t.pattern = 'tests/*_spec.rb'
  t.verbose
end

desc 'Setup test database'
namespace :db do

  desc 'create, setup schema, and load defaults into db. do this on clean install'
  task :setup => [:create, :upgrade, :provision_defaults]
  desc 'create and setup schema'
  task :clean => [:create, :upgrade]
  desc 'destroy db, create db, setup schema, load defaults'
  task :reset => [:destroy, :create, :upgrade, :provision_defaults]
  desc 'destroy db, create db, setup schema'
  task :reset_clean => [:destroy, :create, :upgrade]

  task :create do
    if ENV['RACK_ENV'].nil?
      ENV['RACK_ENV'] = 'development'
    end
    puts "setting up database for environment: #{ENV['RACK_ENV']}"
    config = YAML.load_file('config/database.yml')
    config = config[ENV['RACK_ENV']]
    user, password, host = config['user'], config['password'], config['hostname']
    database = config['database']
    charset = config['charset'] || ENV['CHARSET'] || 'utf8'
    collation = config['collation'] || ENV['COLLATION'] || 'utf8_unicode_ci'

    # create database in mysql for datamapper
    query = [
      'mysql', "--user=#{user}", "--password='#{password}'", "--host=#{host} -e", "CREATE DATABASE #{database} DEFAULT CHARACTER SET #{charset} DEFAULT COLLATE #{collation}".inspect
    ]
    begin
      system(query.compact.join(' '))
    rescue
      raise 'Something went wrong. double check your config/database.yml file and manually test access to mysql.'
    end
  end

  task :destroy do
    if ENV['RACK_ENV'].nil?
      ENV['RACK_ENV'] = 'development'
    end
    puts "destroying database for environment: #{ENV['RACK_ENV']}"
    config = YAML.load_file('config/database.yml')
    config = config[ENV['RACK_ENV']]
    user, password, host = config['user'], config['password'], config['hostname']
    database = config['database']
    charset = config['charset'] || ENV['CHARSET'] || 'utf8'
    collation = config['collation'] || ENV['COLLATION'] || 'utf8_unicode_ci'

    # destroy database in mysql for datamapper
    query = [
      'mysql', "--user=#{user}", "--password='#{password}'", "--host=#{host} -e", "DROP DATABASE #{database}".inspect
    ]
    begin
      system(query.compact.join(' '))
    rescue
      raise 'Something went wrong. double check your config/database.yml file and manually test access to mysql.'
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
      'mysql', "--user=#{user}", "--password='#{password}'", "--host=#{host}", "--database=#{database}", "-e INSERT INTO settings (maxtasktime) VALUES ('68400')".inspect
    ]
    begin
      system(query.compact.join(' '))
    rescue
      raise 'Error in creating default settings'
    end

    puts '[*] Setting up default customer ...'
    # Create Default customer
    query = [
      'mysql', "--user=#{user}", "--password='#{password}'", "--host=#{host}", "--database=#{database}", "-e INSERT INTO customers (name, description) VALUES ('Acme Corp', 'Default Customer')".inspect
    ]
    begin
      system(query.compact.join(' '))
    rescue
      raise 'Error in creating default customer'
    end

    system('gunzip -k control/wordlists/password.gz')
    puts '[*] Settings up default wordlist ...'
    # Create Default Wordlist
    query = [
      'mysql', "--user=#{user}", "--password='#{password}'", "--host=#{host}", "--database=#{database}", "-e INSERT INTO wordlists (name, path, size) VALUES ('DEFAULT WORDLIST', 'control/wordlists/password', '3546')".inspect
    ]
    begin
      system(query.compact.join(' '))
    rescue
      raise 'Error in creating default wordlist'
    end

    # Create Default Task Dictionary
    puts '[*] Setting up default dictionary'
    query = [
      'mysql', "--user=#{user}", "--password='#{password}'", "--host=#{host}", "--database=#{database}", "-e INSERT INTO tasks (name, wl_id, hc_attackmode, hc_rule) VALUES ('Basic Dictionary', '1', 'dictionary', 'none')".inspect
    ]
    begin
      system(query.compact.join(' '))
    rescue
      raise 'Error in creating default dictionary task'
    end

    # Create Default Dictionary + Rule Task
    puts '[*] Setting up default dictionary + rule task'
    query = [
      'mysql', "--user=#{user}", "--password='#{password}'", "--host=#{host}", "--database=#{database}", "-e INSERT INTO tasks (name, wl_id, hc_attackmode, hc_rule) VALUES ('Basic Dictionary + Best64 Rules', '1', 'dictionary', 'best64.rule')".inspect
    ]
    begin
      system(query.compact.join(' '))
    rescue
      raise 'Error in creating default dictionary task + rule'
    end

    # Create Default Mask task
    puts '[*] Setting up default mask task'
    query = [
      'mysql', "--user=#{user}", "--password='#{password}'", "--host=#{host}", "--database=#{database}", "-e INSERT INTO tasks (name, hc_attackmode, hc_mask) VALUES ('Lower Alpha 7char', 'maskmode', '?l?l?l?l?l?l?l')".inspect
    ]
    begin
      system(query.compact.join(' '))
    rescue
      raise 'Error in creating default mask task'
    end

    # Create Default Raw Brute
    puts '[*] Setting up default bute task'
    query = [
      'mysql', "--user=#{user}", "--password='#{password}'", "--host=#{host}", "--database=#{database}", "-e INSERT INTO tasks (name, hc_attackmode) VALUES ('Raw Brute', 'bruteforce')".inspect
    ]
    begin
      system(query.compact.join(' '))
    rescue
      raise 'Error in creating default brute task'
    end
  end

  desc 'Perform non destructive auto migration'
  task :upgrade do
    if ENV['RACK_ENV'].nil?
      ENV['RACK_ENV'] = 'development'
    end
    DataMapper.repository.auto_upgrade!
    puts 'db:auto:upgrade executed'
  end

  desc 'Migrate From old DB to new DB schema'
  task :migrate do
    if ENV['RACK_ENV'].nil?
      ENV['RACK_ENV'] = 'development'
    end

    config = YAML.load_file('config/database.yml')
    config = config[ENV['RACK_ENV']]
    user, password, host = config['user'], config['password'], config['hostname']
    database = config['database']
    charset = config['charset'] || ENV['CHARSET'] || 'utf8'
    collation = config['collation'] || ENV['COLLATION'] || 'utf8_unicode_ci'

    begin

      new_hashes = Set.new

      puts '[*] Connecting to DB'
      conn = Mysql.new host, user, password, database 

      puts '[*] Collecting Table Information...Targets'
      targets_hashfile_id = conn.query('SELECT distinct(hashfile_id) FROM targets')
 
      targets_hashfile_id.each_hash do |hashfile|
        puts '[*] Collecting info for hashfile_id ' + hashfile['hashfile_id']
        hashfileHashes = conn.query("SELECT username,originalhash,hashtype,cracked,plaintext FROM targets where hashfile_id = '" + hashfile['hashfile_id'] + "'")
        hashfileHashes.each_hash do |row|
          originalhash_and_hashtype = row['originalhash'].to_str.downcase + ':' + row['hashtype'].to_str
          new_hashes.add(originalhash_and_hashtype)
        end
      end

      #  Create Table
      puts '[*] Creating new Table: Hashes'
      conn.query("CREATE TABLE IF NOT EXISTS hashes(id INT PRIMARY KEY AUTO_INCREMENT, LastUpdated datetime, originalhash VARCHAR(255), hashtype INT(11), cracked TINYINT(1), plaintext VARCHAR(256))")

      puts '[*] Inserting unique hash data into new table... Please wait, this can take some time....'
      new_hashes.each do | entry |
        originalhash, hashtype = entry.split(':')
        remaining_data = conn.query("SELECT cracked,plaintext FROM targets WHERE originalhash='" + originalhash + "' AND hashtype='" + hashtype + "' LIMIT 1")
        remaining_data.each_hash do | row |
          if row['cracked'] == '1' 
            row['plaintext'] = row['plaintext'].gsub("\\", "\\\\\\") 
            row['plaintext'] = row['plaintext'].gsub("'", "\\\\'")
            conn.query("INSERT INTO hashes(originalhash,hashtype,cracked,plaintext) VALUES ('#{originalhash}','#{hashtype}','#{row['cracked']}','#{row['plaintext']}')")
          else
            conn.query("INSERT INTO hashes(originalhash,hashtype,cracked) VALUES ('#{originalhash}','#{hashtype}','#{row['cracked']}')")
          end
        end
      end

      # Create Table
      puts '[*] Creating new Table: HashfileHashes'
      conn.query("CREATE TABLE IF NOT EXISTS hashfilehashes(id INT PRIMARY KEY AUTO_INCREMENT, hash_id INT(11), username VARCHAR(2000), hashfile_id INT(11))")

      puts '[*] Inserting new data into table... standby..'
      hashes = conn.query("SELECT id,originalhash FROM hashes")
      hashes.each_hash do | entry |
        olddata = conn.query("SELECT username,hashfile_id FROM targets WHERE originalhash='" + entry['originalhash'] + "'")
        hash_id = entry['id']
        olddata.each_hash do | row |
          if row['username'].nil?
            row['username'] = 'none'
          end
          row['username'] = row['username'].gsub("'", "\\\\'")
          conn.query("INSERT INTO hashfilehashes(hash_id,username,hashfile_id) VALUES ('#{hash_id}','#{row['username']}','#{row['hashfile_id']}')")
        end
      end

      # Remove old tables
      puts '[*] Removing old tables'
      conn.query("DROP TABLE targets")


    rescue Mysql::Error => e
      puts e.errno
      puts e.error

    ensure
      conn.close if conn 
    end

  end

end
