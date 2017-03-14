require 'resque/tasks'
require 'resque/scheduler/tasks'
require_relative 'jobs/init'
require 'rake/testtask'
require 'data_mapper'
require 'mysql'
require './models/master.rb'
require './helpers/email.rb'

Rake::TestTask.new do |t|
  t.pattern = 'tests/*_spec.rb'
  t.verbose
end

# resque-scheduler needs to know basics from resque::setup
desc 'Resque scheduler setup'
namespace :resque do
  task :setup do
    require 'resque'

    #Resque.redis = 'localhost:6379'
  end

  task :setup_schedule => :setup do
    require 'resque-scheduler'
    Resque.schedule = YAML.load_file('config/resque_schedule.yml')
  end

  task :scheduler => :setup_schedule
end


desc 'Setup database'
namespace :db do

  desc 'create, setup schema, and load defaults into db. do this on clean install'
  task :setup => [:create, :provision_defaults, :provision_agent]
  desc 'Upgrade your instance of HashView.'
  task :upgrade

  # Are the below ever needed beyond our testing?
  #desc 'create and setup schema'
  #task :clean => [:create] # Should really be made to a series of DELETE FROM
  #desc 'destroy db, create db, setup schema, load defaults'
  #task :reset => [:destroy, :create, :provision_agent, :provision_defaults]
  #desc 'destroy db, create db, setup schema'
  #task :reset_clean => [:destroy, :create, :upgrade, :provision_agent]

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

    # Query for DB Values
    # TODO check for values returned and alert if not true
    query = [
        'mysql', "--user=#{user}", "--password='#{password}'", "--host=#{host} -e", "SELECT @@global.innodb_large_prefix".inspect
    ]
    begin
      system(query.compact.join(' '))
    rescue
      raise 'Something went wrong. double check your config/database.yml file and manually test access to mysql.'
    end

    query = [
        'mysql', "--user=#{user}", "--password='#{password}'", "--host=#{host} -e", "SELECT @@global.innodb_file_format".inspect
    ]
    begin
      system(query.compact.join(' '))
    rescue
      raise 'Something went wrong. double check your config/database.yml file and manually test access to mysql.'
    end

    # create database in mysql for datamapper
    query = [
      'mysql', "--user=#{user}", "--password='#{password}'", "--host=#{host} -e", "CREATE DATABASE #{database} DEFAULT CHARACTER SET #{charset} DEFAULT COLLATE #{collation}".inspect
    ]
    begin
      system(query.compact.join(' '))
    rescue
      raise 'Something went wrong. double check your config/database.yml file and manually test access to mysql.'
    end

    # Creating hashes table
    # Wish we could do this in datamapper, but currently unsupported
    puts 'Creating Hashes Table'
    query = [
        'mysql', "--user=#{user}", "--password='#{password}'", "--host=#{host}", "--database=#{database}", '-e CREATE TABLE IF NOT EXISTS hashes(id INT PRIMARY KEY AUTO_INCREMENT, lastupdated datetime, originalhash VARCHAR(1024), hashtype INT(11), cracked TINYINT(1), plaintext VARCHAR(256), unique index index_of_orignalhashes (originalhash), index index_of_hashtypes (hashtype)) ROW_FORMAT=DYNAMIC'.inspect
    ]
    begin
      system(query.compact.join(' '))
    rescue
      raise "Something went wrong. double check your config/database.yml file and manually test access to mysql. \n Also verify that SELECT '@@global.innodb_large_prefix' and 'SELECT @@global.innodb_file_format' both equal 1"
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
      'mysql', "--user=#{user}", "--password='#{password}'", "--host=#{host}", "--database=#{database}", "-e INSERT INTO hc_settings (max_task_time) VALUES ('86400')".inspect
    ]
    begin
      system(query.compact.join(' '))
    rescue
      raise 'Error in creating default settings'
    end

    puts '[*] Setting default theme ...'
    # Assign Default CSS theme
    query = [
      'mysql', "--user=#{user}", "--password='#{password}'", "--host=#{host}", "--database=#{database}", "-e INSERT INTO settings (ui_themes) VALUES ('Light')".inspect
    ]
    begin
      system(query.compact.join(' '))
    rescue
      raise 'Error in assigning default customer'
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
      'mysql', "--user=#{user}", "--password='#{password}'", "--host=#{host}", "--database=#{database}", "-e INSERT INTO wordlists (name, lastupdated, path, size) VALUES ('DEFAULT WORDLIST', NOW(), 'control/wordlists/password', '3546')".inspect
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

  desc 'Setup local agent'
  task :provision_agent do
    if ENV['RACK_ENV'].nil?
      ENV['RACK_ENV'] = 'development'
    end

    puts "setting up local agent for environment: #{ENV['RACK_ENV']}"
    config = YAML.load_file('config/database.yml')
    config = config[ENV['RACK_ENV']]
    user, password, host = config['user'], config['password'], config['hostname']
    database = config['database']

    agent_config = {}
    agent_config['ip'] = '127.0.0.1'
    agent_config['port'] = '4567'
    agent_config['uuid'] = SecureRandom.uuid.to_s
    File.open('config/agent_config.json', 'w') do |f|
      f.write(JSON.pretty_generate(agent_config))
    end

    puts '[*] Setting up local agent'
    query = [
        'mysql', "--user=#{user}", "--password='#{password}'", "--host=#{host}", "--database=#{database}", "-e INSERT INTO agents (name, uuid, status, src_ip) VALUES ('Local Agent', '#{agent_config['uuid']}', 'Authorized', '127.0.0.1')".inspect
    ]
    begin
      system(query.compact.join(' '))
    rescue
      raise 'Error in provisioning agent'
    end
    puts 'db:provision_agent executed'
  end

  desc 'Perform non destructive auto migration'
  task :upgrade do
    db_version = Gem::Version.new('0.0.0')

    # Check to see what version the app is at
    application_version = File.open('VERSION') {|f| f.readline}

    if ENV['RACK_ENV'].nil?
      ENV['RACK_ENV'] = 'development'
    end

    config = YAML.load_file('config/database.yml')
    config = config[ENV['RACK_ENV']]
    user, password, host = config['user'], config['password'], config['hostname']
    database = config['database']
    charset = config['charset'] || ENV['CHARSET'] || 'utf8'
    collation = config['collation'] || ENV['COLLATION'] || 'utf8_unicode_ci'

    puts '[*] Connecting to DB'
    conn = Mysql.new host, user, password, database

    puts '[*] Collecting table information on Settings'
    settings = conn.query('DESC settings')
    has_version_column = false
    settings.each_hash do |row|
      if row['field'].to_s.downcase == 'version'
        has_version_column = true
        db_version = Gem::Version.new(conn.query('SELECT version FROM SETTINGS'))
      end
    end

    if has_version_column == false
      db_version = Gem::Version.new('0.5.1')
    end

    # TODO turn into hash where version is key, and value is method/function name?
    if Gem::Version.new(db_version) < Gem::Version.new(application_version)
      if Gem::Version.new(db_version) < Gem::Version.new('0.6.0')
        upgrade_to_v060(user, password, host, database)
      end
    end

    # Incase we missed anything
    #DataMapper.repository.auto_upgrade!
    #DataMapper::Model.descendants.each {|m| m.auto_upgrade! if m.superclass == Object}
    #puts 'db:auto:upgrade executed'
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
      conn.query('CREATE TABLE IF NOT EXISTS hashes(id INT PRIMARY KEY AUTO_INCREMENT, lastupdated datetime, originalhash VARCHAR(1024), hashtype INT(11), cracked TINYINT(1), plaintext VARCHAR(256), unique index index_of_orignalhashes (originalhash), index index_of_hashtypes (hashtype)) ROW_FORMAT=DYNAMIC')

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


def upgrade_to_v060(user, password, host, database)
  puts '[*] Upgrading from v0.5.1 to v0.6.0'
  conn = Mysql.new host, user, password, database


  # Check for my.cnf requirements
  puts '[*] Checking for DB requirements'
  has_file_format = `grep 'innodb_file_format = Barracuda' /etc/mysql/my.cnf`
  has_large_prefix = `grep 'innodb_large_prefix = 1' /etc/mysql/my.cnf`
  has_file_per_table = `grep 'innodb_file_per_table = true' /etc/mysql/my.cnf`
  if has_file_format.empty? or has_large_prefix.empty? or has_file_per_table.empty?
    puts '[!] You need to update your SQL configuration: https://github.com/hashview/hashview/wiki/Upgrading-Hashview#upgrading-from-05x-beta-to-060-beta'
    puts '[!] After modifying the file you will need to restart your mysql service'
    exit
  end

  hc_binpath = ''
  max_task_time = ''

  # Collect old settings
  puts '[*] Reading Settings Table.'
  settings = conn.query('SELECT * FROM settings')
  settings.each_hash do |row|
    hc_binpath = row['hcbinpath'].to_s
    max_task_time = row['maxtasktime'].to_s
  end

  puts '[*] Creating new Hashcat Settings table.'
  # Create HcSettings table
  conn.query('CREATE TABLE IF NOT EXISTS HashcatSettings(id INT PRIMARY KEY AUTO_INCREMENT, hc_binpath VARCHAR(2000), max_task_time VARCHAR(2000), opencl_device_types INT, workload_profile INT, gpu_temp_disable BOOLEAN, gpu_temp_abort INT, gpu_temp_retain INT, hc_force BOOLEAN)')
  conn.query("INSERT INTO HashcatSettings(hc_binpath, max_task_time, opencl_device_types, workload_profile, gpu_temp_disable, gpu_temp_abort, gpu_temp_retain, hc_force) VALUES('#{hc_binpath}', '#{max_task_time}', 0, 0, 0, 0, 0, 0)")

  puts '[*] Removing duplicate data from current settings table.'
  # Alter Settings
  conn.query('ALTER TABLE settings DROP COLUMN hcbinpath')
  conn.query('ALTER TABLE settings DROP COLUMN maxtasktime')

  # Add version column
  conn.query('ALTER TABLE settings ADD COLUMN version varchar(5)')

  # Add ui_themes to settings
  # conn.query('ALTER TABLE settings ADD COLUMN ui_themes varchar(')

  puts '[*] Upgrading hashes table. This might take some time. Be patient.'
  # Rename existing table
  conn.query('RENAME TABLE hashes to hashesOld')

  # Create new hashes table
  conn.query('CREATE TABLE IF NOT EXISTS hashesNew(id INT PRIMARY KEY AUTO_INCREMENT, lastupdated datetime, originalhash VARCHAR(1024), hashtype INT(11), cracked TINYINT(1), plaintext VARCHAR(256), unique index index_of_orignalhashes (originalhash), index index_of_hashtypes (hashtype)) ROW_FORMAT=DYNAMIC')

  # Migrate hashes from hashesOld to hashesNew
  old_hashes = conn.query('SELECT * FROM hashesOld')
  old_hashes.each_hash do |row|
    conn.query("INSERT INTO hashesNew(id, lastupdated, originalhash, hashtype, cracked, plaintext) VALUES('#{row['id']}', '#{row['lastupdated']}', '#{row['originalhash']}', '#{row['hashtype']}', '#{row['cracked']}', '#{row['plaintext']}')")
  end

  # Rename HashesNew to hashes
  conn.query('RENAME TABLE hashesNew to hashes')

  # Remove old hashes table
  conn.query('DROP TABLE hashesOld')

  # Create new Agent Table
  conn.query('CREATE TABLE IF NOT EXISTS Agent(id INT PRIMARY KEY AUTO_INCREMENT, name VARCHAR(100), src_ip VARCHAR(45), uuid VARCHAR(60), status VARCHAR(40), hc_status VARCHAR(6000), heartbeat datetime')

  # Create new agent
  puts '[*] Provisioning hashview local agent'

  agent_config = {}
  agent_config['ip'] = '127.0.0.1'
  agent_config['port'] = '4567'
  agent_config['uuid'] = SecureRandom.uuid.to_s
  File.open('config/agent_config.json', 'w') do |f|
    f.write(JSON.pretty_generate(agent_config))
  end

  conn.query.("INSERT INTO agents (name, uuid, status, src_ip) VALUES ('Local Agent', '#{agent_config['uuid']}', 'Authorized', '127.0.0.1')")

  # Update size column for wordlists
  puts '[*] Updating Wordlists'
  conn.query('ALTER TABLE wordlists MODIFY size VARCHAR(100)')

  # FINALIZE UPGRADE
  conn.query("UPDATE settings SET version = '0.6.0'")
  puts '[*] Upgrade to v0.6.0 complete.'
end