require 'resque/tasks'
require 'resque/scheduler/tasks'
require 'rake/testtask'
require 'sequel'
require 'mysql'
# require './models/master.rb'
require './helpers/email.rb'
require './helpers/compute_task_keyspace.rb'
require 'data_mapper'

require_relative 'jobs/init'
# require_relative 'helpers/init'

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
    puts "[*] Setting up database for environment: #{ENV['RACK_ENV']}"
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

    # get reference to database
    db = Sequel.mysql(config)

    # pull in schemma
    # https://github.com/jeremyevans/sequel/blob/master/doc/migration.rdoc
    Sequel::Migrator.run(db, 'db/migrations')
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

    # Create Dynamic Wordlist - all
    puts '[*] Setting up default Dynamic Wordlist [all] ...'
    hash = rand(36**8).to_s(36)
    query = [
        'mysql', "--user=#{user}", "--password='#{password}'", "--host=#{host}", "--database=#{database}", "-e INSERT INTO wordlists (name, type, scope, lastupdated, path, size) VALUES ('Dynamic - [All]', 'dynamic', 'all', NOW(), 'control/wordlists/wordlist-#{hash}.txt', '0')".inspect
    ]
    begin
      system(query.compact.join(' '))
      system('touch control/wordlists/wordlist-' + hash + '.txt')
    rescue
      raise 'Error in creating dynamic wordlists [all]'
    end

    # Create Dynamic Wordlist [customer] - acme
    puts '[*] Setting up default Dynamic Wordlist [customer] - acme ...'
    hash = rand(36**8).to_s(36)
    query = [
        'mysql', "--user=#{user}", "--password='#{password}'", "--host=#{host}", "--database=#{database}", "-e INSERT INTO wordlists (name, type, scope, lastupdated, path, size) VALUES ('Dynamic - [customer] - acme', 'dynamic', 'customer', NOW(), 'control/wordlists/wordlist-#{hash}.txt', '0')".inspect
    ]
    begin
      system(query.compact.join(' '))
      system('touch control/wordlists/wordlist-' + hash + '.txt')
    rescue
      raise 'Error in creating dynamic wordlists [all]'
    end

    # Assign dynamic wordlist to acme customer
    puts '[*] Assigning Dynamic wordlist [customer] acme to acme ...'
    query = [
        'mysql', "--user=#{user}", "--password='#{password}'", "--host=#{host}", "--database=#{database}", "-e UPDATE customers SET wl_id = '2' where id = '1'".inspect
    ]
    begin
      system(query.compact.join(' '))
    rescue
      raise 'Error in assigning Dynamic Wordlist [customer] - acme'
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
      'mysql', "--user=#{user}", "--password='#{password}'", "--host=#{host}", "--database=#{database}", "-e INSERT INTO tasks (name, wl_id, hc_attackmode, hc_rule) VALUES ('Basic Dictionary', '4', 'dictionary', 'none')".inspect
    ]
    begin
      system(query.compact.join(' '))
    rescue
      raise 'Error in creating default dictionary task'
    end

    # Create Default Dictionary + Rule Task
    puts '[*] Setting up default dictionary + rule task'
    query = [
      'mysql', "--user=#{user}", "--password='#{password}'", "--host=#{host}", "--database=#{database}", "-e INSERT INTO tasks (name, wl_id, hc_attackmode, hc_rule) VALUES ('Basic Dictionary + hob064 Rules', '3', 'dictionary', '5')".inspect
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

    puts "[*] Setting up local agent for environment: #{ENV['RACK_ENV']}"
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
    puts '[*] provision_agent executed'
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
      # Upgrade to v0.7.4
      if Gem::Version.new(db_version) < Gem::Version.new('0.7.4')
        upgrade_to_v074(user, password, host, database)
      end
    else
      puts '[*] Your version is up to date!'
    end

    # In case we missed anything
    # DataMapper.repository.auto_upgrade!
    # DataMapper::Model.descendants.each {|m| m.auto_upgrade! if m.superclass == Object}
    # puts 'db:auto:upgrade executed'
  end

  desc 'Perform a sequel db migration'
  task :migrate do
    # should be replaced with https://github.com/jeremyevans/sequel/blob/master/doc/migration.rdoc
    if ENV['RACK_ENV'].nil?
      ENV['RACK_ENV'] = 'development'
    end

    config = YAML.load_file('config/database.yml')
    config = config[ENV['RACK_ENV']]
    user, password, host = config['user'], config['password'], config['host']
    database = config['database']

    db = Sequel.mysql(config)
    Sequel::Migrator.run(db, 'db/migrations')

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
  puts '[*] Upgrading from v0.7.2 to v0.7.3'
  conn = Mysql.new host, user, password, database

  puts '[*] Adding new column for hashcat settings.'
  conn.query('ALTER TABLE hashcat_settings ADD COLUMN optimized_drivers tinyint(1)')
  conn.query('UPDATE hashcat_settings set optimized_drivers = "0" where optimized_drivers is NULL')
  # do database migrations
  # we normally do this but since this is our first migration to sequel and we have not db changes. We comment it out.
  # db = Sequel.mysql(config)
  # Sequel::Migrator.run(db, "db/migrations")

  # FINALIZE UPGRADE
  conn.query('UPDATE settings SET version = \'0.7.3\'')
  puts '[+] Upgrade to v0.7.3 complete.'
end

def upgrade_to_v074(user, password, host, database)
  puts '[*] Upgrading from v0.7.3 to v0.7.4'
  puts '[*] Updating DB to support UTF-8, More Connections, and Longer pool timeouts.'
  system('sed -i \'s/database: "hashview"/database: "hashview"\n  encoding: "utf8"\n  max_connections: "10"\n  pool_timeout: "600"/\' config/database.yml')
  system('sed -i \'s/database: "hashview_dev"/database: "hashview_dev"\n  encoding: "utf8"\n  max_connections: "10"\n  pool_timeout: "600"/\' config/database.yml')
  system('sed -i \'s/database: "hashview_test"/database: "hashview_test"\n  encoding: "utf8"\n  max_connections: "10"\n  pool_timeout: "600"/\' config/database.yml')

  conn = Mysql.new host, user, password, database
  # Creating New Task Groups Table
  conn.query('CREATE TABLE IF NOT EXISTS task_groups(id INT PRIMARY KEY AUTO_INCREMENT, name VARCHAR(255), tasks VARCHAR(1024))')

  # Adding new columns
  puts '[*] Adding new columns.'
  conn.query('ALTER TABLE hashfiles ADD COLUMN wl_id int(10)')
  conn.query('ALTER TABLE customers ADD COLUMN wl_id int(10)')
  conn.query('ALTER TABLE jobtasks ADD COLUMN keyspace_pos BIGINT')
  conn.query('ALTER TABLE jobtasks ADD COLUMN keyspace BIGINT')
  conn.query('ALTER TABLE wordlists ADD COLUMN scope varchar(25)')

  # Altering columns
  puts '[*] Renaming existing columns.'
  conn.query('ALTER TABLE jobs CHANGE COLUMN last_updated_by owner varchar(40)')
  conn.query('ALTER TABLE jobtasks CHANGE COLUMN build_cmd command varchar(4000)')

  # Removing old smart wordlist
  puts '[*] Removing Smart Wordlists.'
  require_relative 'models/master'
  wordlist = Wordlists.first(path: 'control/wordlists/SmartWordlist.txt')

  # Remove from any existing job (keep job)
  @tasks = Tasks.where(wl_id: wordlist.id).all
  @tasks.each do |task|
    @jobtasks = HVDB[:jobtasks]
    @jobtasks.filter(task_id: task.id).delete
  end

  # Remove from any tasks
  @tasks = HVDB[:tasks]
  @tasks.filter(wl_id: wordlist.id).delete

  # Remove from filesystem
  begin
    File.delete(wordlist.path)
  rescue
    puts '[!] No file found on disk.'
  end
  
  # Remove from db
  wordlist = HVDB[:wordlists]
  wordlist.filter(path: 'control/wordlists/SmartWordlist.txt').delete

  # Create a dynamic wordlist for each hashfile
  puts '[*] Creating new dynamic wordlists for existing hashfiles.'

  @hashfiles = Hashfiles.all
  @hashfiles.each do |entry|
    hash = rand(36**8).to_s(36)
    wordlist = Wordlists.new
    wordlist.type = 'dynamic'
    wordlist.scope = 'hashfile'
    wordlist.name = 'DYNAMIC [hashfile] - ' + entry[:name].to_s
    wordlist.path = 'control/wordlists/wordlist-' + hash + '.txt'
    wordlist.size = 0
    wordlist.checksum = nil
    wordlist.lastupdated = Time.now
    wordlist.save

    # Create Shell file
    file_shell = File.new('control/wordlists/wordlist-' + hash + '.txt', 'w')
    file_shell.close
    
    entry.wl_id = wordlist.id
    entry.save
  end

  # Create a dynamic wordlist for each customer
  puts '[*] Creating new dynamic wordlists for existing customers.'
  @customers = Customers.all
  @customers.each do |entry|
    hash = rand(36**8).to_s(36)
    wordlist = Wordlists.new
    wordlist.type = 'dynamic'
    wordlist.scope = 'customer'
    wordlist.name = 'DYNAMIC [customer] - ' + entry[:name].to_s
    wordlist.path = 'control/wordlists/wordlist-' + hash + '.txt'
    wordlist.size = 0
    wordlist.checksum = nil
    wordlist.lastupdated = Time.now
    wordlist.save
    
    # Create Shell file
    file_shell = File.new('control/wordlists/wordlist-' + hash + '.txt', 'w')
    file_shell.close

    entry.wl_id = wordlist.id
    entry.save
  end

  # Create a dynamic wordlist for entire DB
  puts '[*] Creating new dynamic wordlists for Hashview.'
  hash = rand(36**8).to_s(36)
  wordlist = Wordlists.new
  wordlist.type = 'dynamic'
  wordlist.scope = 'all'
  wordlist.name = 'DYNAMIC [ALL]'
  wordlist.path = 'control/wordlists/wordlist-' + hash + '.txt'
  wordlist.size = 0
  wordlist.checksum = nil
  wordlist.lastupdated = Time.now
  wordlist.save
  
  # Create Shell file
  file_shell = File.new('control/wordlists/wordlist-' + hash + '.txt', 'w')
  file_shell.close

  puts '[*] Updating existing tasks keyspace'
  @tasks = Tasks.all
  @tasks.each do |task|
    if task.keyspace.nil? || task.keyspace == 0
      task.keyspace = getKeyspace(task)
      task.save
    end
  end

  # FINALIZE UPGRADE
  conn.query('UPDATE settings SET version = \'0.7.4\'')
  puts '[+] Upgrade to v0.7.4 complete.'
end
