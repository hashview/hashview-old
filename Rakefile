require 'resque/tasks'
require 'resque/scheduler/tasks'
require 'rake/testtask'
require 'sequel'
require 'mysql'
#require './models/master.rb'
require './helpers/email.rb'
require './helpers/smartWordlist.rb'
require './helpers/compute_task_keyspace.rb'
require 'data_mapper'

require_relative 'jobs/init'
#require_relative 'helpers/init'

Sequel.extension :migration, :core_extensions

Rake::TestTask.new do |t|
  t.pattern = 'tests/*_spec.rb'
  t.verbose
end

# Catching Sigterm
def shut_down
  puts 'Attempting to shutdown gracefully...'
  # Technique based off of https://bugs.ruby-lang.org/issue/7917
  # and
  # https://stackoverflow.com/questions/7416318/how-do-i-clear-stuck-stale-resque-workers
  t = Thread.new do
    Resque.workers.each {| w | w.unregister_worker}
  end
  t.join
  sleep(5)
end

# Trap ^C
Signal.trap('INT') {
  shut_down
  exit
}

# Trap `kill `
Signal.trap('TERM') {
  shut_down
  exit
}

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
  desc 'Drop from all tables except users and task'
  task :reset

  task :create do
    if ENV['RACK_ENV'].nil?
      ENV['RACK_ENV'] = 'development'
    end
    puts "setting up database for environment: #{ENV['RACK_ENV']}"
    config = YAML.load_file('config/database.yml')
    config = config[ENV['RACK_ENV']]
    user, password, host = config['user'], config['password'], config['host']
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

    # create database
    Sequel.connect(config.merge('database' => 'mysql')) do |db|
      #db.execute "DROP DATABASE IF EXISTS #{config['database']}"
      db.execute "CREATE DATABASE #{config['database']} DEFAULT CHARACTER SET #{charset} DEFAULT COLLATE #{collation}"
    end

    #get reference to database
    db = Sequel.mysql(config)    
    
    #pull in schemma
    #https://github.com/jeremyevans/sequel/blob/master/doc/migration.rdoc
    Sequel::Migrator.run(db, './config/db/')
  end

  task :destroy do
    if ENV['RACK_ENV'].nil?
      ENV['RACK_ENV'] = 'development'
    end
    puts "destroying database for environment: #{ENV['RACK_ENV']}"
    config = YAML.load_file('config/database.yml')
    config = config[ENV['RACK_ENV']]

    # destroy database in mysql 
    Sequel.connect(config.merge('database' => 'mysql')) do |db|
      db.execute "DROP DATABASE IF EXISTS #{config['database']}"
    end
  end

  task :reset do
    if ENV['RACK_ENV'].nil?
      ENV['RACK_ENV'] = 'development'
    end
    puts "removing all data in the database for environment: #{ENV['RACK_ENV']}"
    config = YAML.load_file('config/database.yml')
    config = config[ENV['RACK_ENV']]
    user, password, host = config['user'], config['password'], config['host']
    database = config['database']

    tables = [ 'customers','hashes','hashfilehashes','hashfiles','jobs','jobtasks','rules','sessions','taskqueues','wordlists' ]
    tables.each do |table|
      query = [
        'mysql', "--user=#{user}", "--password='#{password}'", "--host=#{host}","--database=#{database} -e", "TRUNCATE TABLE #{table}".inspect
      ]
      begin
        system(query.compact.join(' '))
      rescue
        raise 'Something went wrong. double check your config/database.yml file and manually test access to mysql.'
      end
    end
  end

  task :provision_defaults do
    config = YAML.load_file('config/database.yml')
    config = config[ENV['RACK_ENV']]
    user, password, host = config['user'], config['password'], config['host']
    database = config['database']

    puts '[*] Setting up default settings ...'
    # Create Default Settings
    query = [
      'mysql', "--user=#{user}", "--password='#{password}'", "--host=#{host}", "--database=#{database}", "-e INSERT INTO hashcat_settings (max_task_time) VALUES ('86400')".inspect
    ]
    begin
      system(query.compact.join(' '))
    rescue
      raise 'Error in creating default settings'
    end

    puts '[*] Setting default theme ...'
    # Assign Default CSS theme and set version

    # Check to see what version the app is at
    application_version = File.open('VERSION') {|f| f.readline}

    query = [
      'mysql', "--user=#{user}", "--password='#{password}'", "--host=#{host}", "--database=#{database}", "-e INSERT INTO settings (ui_themes, version) VALUES ('Light','#{application_version}')".inspect
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

    # Create Smart Wordlist
    puts '[*] Setting up default Smart Wordlist ...'
    query = [
        'mysql', "--user=#{user}", "--password='#{password}'", "--host=#{host}", "--database=#{database}", "-e INSERT INTO wordlists (name, type, lastupdated, path, size) VALUES ('Smart Wordlist', 'dynamic', NOW(), 'control/wordlists/SmartWordlist.txt', '0')".inspect
    ]
    begin
      system(query.compact.join(' '))
      system('touch control/wordlists/SmartWordlist.txt')
    rescue
      raise 'Error in creating smart wordlist'
    end

    puts '[*] Settings up default wordlist ...'
    # Create Default Wordlist
    system('gunzip -k control/wordlists/password.gz')
    query = [
      'mysql', "--user=#{user}", "--password='#{password}'", "--host=#{host}", "--database=#{database}", "-e INSERT INTO wordlists (name, type, lastupdated, path, size) VALUES ('DEFAULT WORDLIST', 'static', NOW(), 'control/wordlists/password', '3546')".inspect
    ]
    begin
      system(query.compact.join(' '))
    rescue
      raise 'Error in creating default wordlist'
    end

    # Create Default Task Dictionary
    puts '[*] Setting up default dictionary'
    query = [
      'mysql', "--user=#{user}", "--password='#{password}'", "--host=#{host}", "--database=#{database}", "-e INSERT INTO tasks (name, wl_id, hc_attackmode, hc_rule) VALUES ('Basic Dictionary', '2', 'dictionary', 'none')".inspect
    ]
    begin
      system(query.compact.join(' '))
    rescue
      raise 'Error in creating default dictionary task'
    end

    # Create Default Dictionary + Rule Task
    puts '[*] Setting up default dictionary + rule task'
    query = [
      'mysql', "--user=#{user}", "--password='#{password}'", "--host=#{host}", "--database=#{database}", "-e INSERT INTO tasks (name, wl_id, hc_attackmode, hc_rule) VALUES ('Basic Dictionary + hob064 Rules', '2', 'dictionary', '5')".inspect
    ]
    begin
      system(query.compact.join(' '))
    rescue
      raise 'Error in creating default dictionary task + rule'
    end

    # Create Default SmartWordlist Dictionary
    puts '[*] Setting up default smart wordlist task'
    query = [
      'mysql', "--user=#{user}", "--password='#{password}'", "--host=#{host}", "--database=#{database}", "-e INSERT INTO tasks (name, wl_id, hc_attackmode) VALUES ('Smart Wordlist Dictionary', '1', 'dictionary')".inspect
    ]
    begin
      system(query.compact.join(' '))
    rescue
      raise 'Error in creating default SmartWordlist task'
    end

    # Create Default SmartWordlist Dictionary + Rule Task
    puts '[*] Setting up Smart Wordlist dictionary + rule task'
    query = [
      'mysql', "--user=#{user}", "--password='#{password}'", "--host=#{host}", "--database=#{database}", "-e INSERT INTO tasks (name, wl_id, hc_attackmode, hc_rule) VALUES ('Smart Wordlist Dictionary + hob064 Rules', '1', 'dictionary', '5')".inspect
    ]
    begin
      system(query.compact.join(' '))
    rescue
      raise 'Error in creating Smart Wordlist dictionary task + rule'
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
    puts '[*] Setting up default brute task'
    query = [
      'mysql', "--user=#{user}", "--password='#{password}'", "--host=#{host}", "--database=#{database}", "-e INSERT INTO tasks (name, hc_attackmode) VALUES ('Raw Brute', 'bruteforce')".inspect
    ]
    begin
      system(query.compact.join(' '))
    rescue
      raise 'Error in creating default brute task'
    end

    # Create Default Hub Settings
    puts '[*] Setting up default hub settings'
    query = [
      'mysql', "--user=#{user}", "--password='#{password}'", "--host=#{host}", "--database=#{database}", "-e INSERT INTO hub_settings (status) VALUES ('unregistered')".inspect
    ]
    begin
      system(query.compact.join(' '))
    rescue
      raise 'Error in creating default hub settings'
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
    user, password, host = config['user'], config['password'], config['host']
    database = config['database']

    agent_config = {}
    agent_config['ip'] = '127.0.0.1'
    agent_config['port'] = '4567'
    agent_config['uuid'] = SecureRandom.uuid.to_s
    agent_config['hc_binary_path'] = ''
    agent_config['type'] = 'master'
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
    puts 'provision_agent executed'
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
    user, password, host = config['user'], config['password'], config['host']
    database = config['database']

    puts '[*] Connecting to DB'
    conn = Mysql.new host, user, password, database

    puts '[*] Collecting table information on Settings'
    #settings = conn.query('DESC settings')
    settings = conn.query('SELECT * FROM settings')
    has_version_column = false
    settings.each_hash do |row|
      if row['version']
        has_version_column = true
        db_version = Gem::Version.new(row['version'])
      end
    end

    db_version = Gem::Version.new('0.5.1') unless has_version_column

    # TODO turn into hash where version is key, and value is method/function name?
    if Gem::Version.new(db_version) < Gem::Version.new(application_version)
      # Upgrade to v0.6.0
      if Gem::Version.new(db_version) < Gem::Version.new('0.6.0')
        db_version = upgrade_to_v060(user, password, host, database)
      end

      # Upgrade to v0.6.1
      if Gem::Version.new(db_version) < Gem::Version.new('0.6.1')
        db_version = upgrade_to_v061(user, password, host, database)
      end
      # Upgrade to v0.7.0
      if Gem::Version.new(db_version) < Gem::Version.new('0.7')
        upgrade_to_v070(user, password, host, database)
      end
      # Upgrade to v0.7.1
      if Gem::Version.new(db_version) < Gem::Version.new('0.7.1')
        upgrade_to_v071(user, password, host, database)
      end
      # Upgrade to v0.7.2
      if Gem::Version.new(db_version) < Gem::Version.new('0.7.2')
        upgrade_to_v072(user, password, host, database)
      end
      # Upgrade to v0.7.3
      if Gem::Version.new(db_version) < Gem::Version.new('0.7.3')
        upgrade_to_v073(user, password, host, database)
      end
    else
      puts '[*] Your version is up to date!'
    end

    # Incase we missed anything
    #DataMapper.repository.auto_upgrade!
    # DataMapper::Model.descendants.each {|m| m.auto_upgrade! if m.superclass == Object}
    # puts 'db:auto:upgrade executed'
  end

  desc 'Migrate From old DB to new DB schema'
  task :migrate do
    #should be replaced with https://github.com/jeremyevans/sequel/blob/master/doc/migration.rdoc
    if ENV['RACK_ENV'].nil?
      ENV['RACK_ENV'] = 'development'
    end

    config = YAML.load_file('config/database.yml')
    config = config[ENV['RACK_ENV']]
    user, password, host = config['user'], config['password'], config['host']
    database = config['database']

    Sequel::Migrator.check_current(DB, '/path/to/migrations')
    db = Sequel.mysql(database)
    Sequel::Migrator.run(db, "db/migrations")

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
      hashes.each_hash do |entry|
        olddata = conn.query("SELECT username,hashfile_id FROM targets WHERE originalhash='" + entry['originalhash'] + "'")
        hash_id = entry['id']
        olddata.each_hash do |row|
          row['username'] = 'none' if row['username'].nil?
          row['username'] = row['username'].gsub("'", "\\\\'")
          conn.query("INSERT INTO hashfilehashes(hash_id,username,hashfile_id) VALUES ('#{hash_id}','#{row['username']}','#{row['hashfile_id']}')")
        end
      end

      # Remove old tables
      puts '[*] Removing old tables'
      conn.query('DROP TABLE targets')

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
  # Large file Prefix?
  value = conn.query('SELECT @@global.innodb_large_prefix')
  value.each do |row|
    unless row[0] == '1'
      puts '[!] Upgrade Failed. Mysql Prerequisites not met. Did you follow the steps outlined here: https://github.com/hashview/wiki/Upgradeing-Hashview#upgrading-from-05x-to-060-beta'
      puts '[!] After modifying the file you will need to restart your mysql service'
    end
  end

  # Large File Format?
  value = conn.query('SELECT @@global.innodb_file_format')
  value.each do |row|
    unless row[0] == 'Barracuda'
      puts '[!] Upgrade Failed. Mysql Prerequisites not met. Did you follow the steps outlined here: https://github.com/hashview/wiki/Upgradeing-Hashview#upgrading-from-05x-to-060-beta'
      puts '[!] After modifying the file you will need to restart your mysql service'
    end
  end

  # File per table?
  value = conn.query('SELECT @@global.innodb_file_per_table')
  value.each do |row|
    unless row[0] == '1'
      puts '[!] Upgrade Failed. Mysql Prerequisites not met. Did you follow the steps outlined here: https://github.com/hashview/wiki/Upgradeing-Hashview#upgrading-from-05x-to-060-beta'
      puts '[!] After modifying the file you will need to restart your mysql service'
    end
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
  # Create HashcatSettings table
  # note class name HashcatSettings and tablename hashcat_settings differ... this is because ... reasons
  conn.query('CREATE TABLE IF NOT EXISTS hashcat_settings(id INT PRIMARY KEY AUTO_INCREMENT, hc_binpath VARCHAR(2000), max_task_time VARCHAR(2000), opencl_device_types INT, workload_profile INT, gpu_temp_disable BOOLEAN, gpu_temp_abort INT, gpu_temp_retain INT, hc_force BOOLEAN)')
  conn.query("INSERT INTO hashcat_settings(hc_binpath, max_task_time, opencl_device_types, workload_profile, gpu_temp_disable, gpu_temp_abort, gpu_temp_retain, hc_force) VALUES('#{hc_binpath}', '#{max_task_time}', 0, 0, 0, 0, 0, 0)")

  puts '[*] Removing duplicate data from current settings table.'
  # Alter Settings
  conn.query('ALTER TABLE settings DROP COLUMN hcbinpath')
  conn.query('ALTER TABLE settings DROP COLUMN maxtasktime')

  # Add version & SMTP_SENDER column
  conn.query('ALTER TABLE settings ADD COLUMN version varchar(5)')
  conn.query('ALTER TABLE settings ADD COLUMN smtp_sender varchar(50)')

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
    if row['cracked'] == '1'
      row['plaintext'] = row['plaintext'].gsub("\\", "\\\\\\")
      row['plaintext'] = row['plaintext'].gsub("'", "\\\\'")
    end
    row['originalhash'] = row['originalhash'].gsub("\\", "\\\\\\")
    row['originalhash'] = row['originalhash'].gsub("'", "\\\\'")
    conn.query("INSERT INTO hashesNew(id, lastupdated, originalhash, hashtype, cracked, plaintext) VALUES('#{row['id']}', '#{row['lastupdated']}', '#{row['originalhash']}', '#{row['hashtype']}', '#{row['cracked']}', '#{row['plaintext']}')")
  end

  # Rename HashesNew to hashes
  conn.query('RENAME TABLE hashesNew to hashes')

  # Remove old hashes table
  conn.query('DROP TABLE hashesOld')

  # Create new Agent Table
  conn.query('CREATE TABLE IF NOT EXISTS agents(id INT PRIMARY KEY AUTO_INCREMENT, name VARCHAR(100), src_ip VARCHAR(45), uuid VARCHAR(60), status VARCHAR(40), hc_status VARCHAR(6000), heartbeat datetime)')

  # Create new agent
  puts '[*] Provisioning Hashview local agent'

  agent_config = {}
  agent_config['ip'] = '127.0.0.1'
  agent_config['port'] = '4567'
  agent_config['uuid'] = SecureRandom.uuid.to_s
  agent_config['hc_binary_path'] = ''
  agent_config['type'] = 'master'
  File.open('config/agent_config.json', 'w') do |f|
    f.write(JSON.pretty_generate(agent_config))
  end

  conn.query("INSERT INTO agents(name, uuid, status, src_ip) VALUES ('Local Agent', '#{agent_config['uuid']}', 'Authorized', '127.0.0.1')")

  # Update size column for wordlists
  puts '[*] Updating Wordlists'
  conn.query('ALTER TABLE wordlists MODIFY size VARCHAR(100)')

  # FINALIZE UPGRADE
  conn.query("UPDATE settings SET version = '0.6.0'")
  puts '[*] Upgrade to v0.6.0 complete.'

  '0.6.0'
end

def upgrade_to_v061(user, password, host, database)
  #DataMapper.repository.auto_upgrade!
  DataMapper::Model.descendants.each { |m| m.auto_upgrade! if m.superclass == Object }

  puts '[*] Upgrading from v0.6.0 to v0.6.1'
  conn = Mysql.new host, user, password, database

  # FINALIZE UPGRADE
  conn.query("UPDATE settings SET version = '0.6.1'")
  puts '[*] Upgrade to v0.6.1 complete.'

  '0.6.1'
end

def upgrade_to_v070(user, password, host, database)
  DataMapper.repository.auto_upgrade!
  DataMapper::Model.descendants.each { |m| m.auto_upgrade! if m.superclass == Object }

  puts '[*] Upgrading from v0.6.1 to v0.7.0'
  conn = Mysql.new host, user, password, database

  # this upgrade path doesn't require anything complex, just move a value from db to config file
  puts '[*] Reading Settings Table.'
  hashcat_settings = conn.query('SELECT hc_binpath FROM hashcat_settings')
  hashcat_settings.each_hash do |row|
    @hc_binpath = row['hc_binpath'].to_s
  end

  # add new parameters to local agent config
  puts '[*] Writing new parameters to agent config'
  agent_config = JSON.parse(File.read('config/agent_config.json'))
  agent_config['hc_binary_path'] = @hc_binpath
  agent_config['type'] = 'master'
  File.open('config/agent_config.json', 'w') do |f|
    f.write(JSON.pretty_generate(agent_config))
  end

  # Set existing wordlists to static (we should have any smart word lists atm)
  puts '[*] Setting existing wordlist types'
  @wordlists = Wordlists.all
  @wordlists.each do |entry|
    entry.type = 'static'
    entry.save
  end

  # Create new smart word list
  # should probably be moved to first but we'd break existing tasks
  puts '[*] Generating Smart Wordlist ... this could take some time be patient'
  updateSmartWordlist

  # Identify all wordlists without checksums
  @wordlist = Wordlists.where(checksum: nil).all
  @wordlist.each do |wl|
    # generate checksum
    puts 'generating checksum'
    checksum = Digest::SHA2.hexdigest(File.read(wl.path))

    # save checksum to database
    wl.checksum = checksum
    wl.save
  end

  # add existing rules to db
  # this is not DRY, oh well, gotta ship code before blackhat!
  puts '[*] Add existing rules to database'
  # Identify all rules in directory
  @files = Dir.glob(File.join('control/rules/', '*.rule'))
  @files.each do |path_file|
    rule_entry = Rules.first(path: path_file)
    unless rule_entry
      # Get Name
      name = path_file.split('/')[-1]

      puts 'Importing new Rule file "' + name + '" into HashView.'

      # Adding to DB
      rule_file = Rules.new
      rule_file.lastupdated = Time.now
      rule_file.name = name
      rule_file.path = path_file
      rule_file.size = 0
      rule_file.checksum = Digest::SHA2.hexdigest(File.read(path_file))
      rule_file.save

    end
  end

  # compute keyspace for existing tasks
  puts '[*] Computing keyspace for existing tasks'
  @tasks = Tasks.all
  @tasks.each do |task|
    task.keyspace = getKeyspace(task)
    task.save
  end

  # transpose rules from name to id in existing tasks
  puts '[*] Edit how rules are defined in existing tasks'
  @tasks = Tasks.all
  @tasks.each do |task|
    rule = Rules.first(name: task.hc_rule)
    unless rule.nil?
      task.hc_rule = rule.id
      task.save
    end
  end

  # Populating hub settings table entry
  puts '[*] Populating Hub Settings'
  @hub_settings = HubSettings.first
  if @hub_settings.nil?
    @hub_settings = HubSettings.create
    @hub_settings = HubSettings.first

    if @hub_settings.uuid.nil?
      uuid = SecureRandom.hex(10)
      # Add hyphens, (i am ashamed at how dumb this is)
      uuid.insert(15, '-')
      uuid.insert(10, '-')
      uuid.insert(5, '-')
      @hub_settings.uuid = uuid
      @hub_settings.save
    end
  end

  # FINALIZE UPGRADE
  conn.query("UPDATE settings SET version = '0.7.0'")
  puts '[+] Upgrade to v0.7.0 complete.'
end

def upgrade_to_v071(user, password, host, database)

  DataMapper::Model.descendants.each { |m| m.auto_upgrade! if m.superclass == Object }
  puts '[*] Upgrading from v0.7.0 to v0.7.1'
  conn = Mysql.new host, user, password, database

  # FINALIZE UPGRADE
  conn.query("UPDATE settings SET version = '0.7.1'")
  puts '[+] Upgrade to v0.7.1 complete.'
end

def upgrade_to_v072(user, password, host, database)
  DataMapper::Model.descendants.each { |m| m.auto_upgrade! if m.superclass == Object }

  puts '[*] Upgrading from v0.7.1 to v0.7.2'
  conn = Mysql.new host, user, password, database

  # Remove unused columns
  puts '[*] Removing unused database structures.'
  conn.query('ALTER TABLE jobs DROP COLUMN policy_min_pass_length')
  conn.query('ALTER TABLE jobs DROP COLUMN policy_complexity_default')
  conn.query('ALTER TABLE jobs DROP COLUMN targettype')
  conn.query('ALTER TABLE settings DROP COLUMN clientmode')

  # Updating database config file
  puts '[*] Fixing db config entries.'
  File.rename('config/database.yml', 'config/database.yml.old')
  config_content = File.read('config/database.yml.old').gsub(/hostname:/, 'host:')
  File.open('config/database.yml', 'w') do |out|
    out << config_content
  end
  File.delete('config/database.yml.old')

  # FINALIZE UPGRADE
  conn.query('UPDATE settings SET version = \'0.7.2\'')
  puts '[+] Upgrade to v0.7.2 complete.'
end

def upgrade_to_v073(user, password, host, database)
  DataMapper::Model.descendants.each { |m| m.auto_upgrade! if m.superclass == Object }

  puts '[*] Upgrading from v0.7.2 to v0.7.3'
  conn = Mysql.new host, user, password, database
  #db = Sequel.mysql(database)
  #Sequel::Migrator.run(db, "db/migrations")

  # FINALIZE UPGRADE
  conn.query('UPDATE settings SET version = \'0.7.3\'')
  puts '[+] Upgrade to v0.7.3 complete.'
end
