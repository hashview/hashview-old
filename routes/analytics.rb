# encoding: utf-8
require 'json'

# displays analytics for a specific client, job
get '/analytics' do
  varWash(params)
  
  @customer_id = params[:customer_id]
  @hashfile_id = params[:hashfile_id]
  @button_select_customers = Customers.all(order: [:name.asc])
  
  if params[:customer_id] && !params[:customer_id].empty?
    @button_select_hashfiles = Hashfiles.all(customer_id: params[:customer_id])
  end
  
  if params[:customer_id] && !params[:customer_id].empty?
    @customers = Customers.first(id: params[:customer_id])
  else
    @customers = Customers.all(order: [:name.asc])
  end
  
  if params[:customer_id] && !params[:customer_id].empty?
    if params[:hashfile_id] && !params[:hashfile_id].empty?
      @hashfiles = Hashfiles.first(id: params[:hashfile_id])
    else
      @hashfiles = Hashfiles.all
    end
  end
  
  # get results of specific customer if customer_id is defined
  # if we have a customer
  if params[:customer_id] && !params[:customer_id].empty?
    # if we have a hashfile
    if params[:hashfile_id] && !params[:hashfile_id].empty?
      # Used for Total Hashes Cracked doughnut: Customer: Hashfile
      @cracked_pw_count = repository(:default).adapter.select('SELECT COUNT(h.originalhash) FROM hashes h LEFT JOIN hashfilehashes a ON h.id = a.hash_id WHERE (a.hashfile_id = ? AND h.cracked = 1)', params[:hashfile_id])[0].to_s
      @uncracked_pw_count = repository(:default).adapter.select('SELECT COUNT(h.originalhash) FROM hashes h LEFT JOIN hashfilehashes a ON h.id = a.hash_id WHERE (a.hashfile_id = ? AND h.cracked = 0)', params[:hashfile_id])[0].to_s
 
      # Used for Total Accounts table: Customer: Hashfile
      @total_accounts = @uncracked_pw_count.to_i + @cracked_pw_count.to_i
  
      # Used for Total Unique Users and originalhashes Table: Customer: Hashfile
      @total_users_originalhash = repository(:default).adapter.select('SELECT a.username, h.originalhash FROM hashes h LEFT JOIN hashfilehashes a ON h.id = a.hash_id LEFT JOIN hashfiles f on a.hashfile_id = f.id WHERE (f.customer_id = ? AND f.id = ?)', params[:customer_id],params[:hashfile_id])
  
      @total_unique_users_count = repository(:default).adapter.select('SELECT COUNT(DISTINCT(username)) FROM hashfilehashes WHERE hashfile_id = ?', params[:hashfile_id])[0].to_s
      @total_unique_originalhash_count = repository(:default).adapter.select('SELECT COUNT(DISTINCT(h.originalhash)) FROM hashes h LEFT JOIN hashfilehashes a ON h.id = a.hash_id WHERE a.hashfile_id = ?', params[:hashfile_id])[0].to_s
  
      # Used for Total Run Time: Customer: Hashfile
      @total_run_time = Hashfiles.first(fields: [:total_run_time], id: params[:hashfile_id]).total_run_time
  
      # make list of unique hashes
      unique_hashes = Set.new
      @total_users_originalhash.each do |entry|
        unique_hashes.add(entry.originalhash)
      end
  
      hashes = []
      # create array of all hashes to count dups
      @total_users_originalhash.each do |uh|
        unless uh.originalhash.nil?
          hashes << uh.originalhash unless uh.originalhash.empty?
        end
      end
  
      @duphashes = {}
      # count dup hashes
      hashes.each do |hash|
        if @duphashes[hash].nil?
          @duphashes[hash] = 1
        else
          @duphashes[hash] += 1
        end
      end
      # this will only display top 10 hash/passwords shared by users
      @duphashes = Hash[@duphashes.sort_by { |_k, v| -v }[0..20]]
  
      users_same_password = []
      @password_users = {}
      # for each unique password hash find the users and their plaintext
      @duphashes.each do |hash|
        dups = repository(:default).adapter.select('SELECT a.username, h.plaintext, h.cracked FROM hashes h LEFT JOIN hashfilehashes a on h.id = a.hash_id LEFT JOIN hashfiles f on a.hashfile_id = f.id WHERE (f.customer_id = ? AND f.id = ? AND h.originalhash = ?)', params[:customer_id], params[:hashfile_id], hash[0] )
        # for each user with the same password hash add user to array
        dups.each do |d|
          if !d.username.nil?
            users_same_password << d.username
          else
            users_same_password << 'NULL'
          end
          if d.cracked
            hash[0] = d.plaintext
          end
        end
        # assign array of users to hash of similar password hashes
        if users_same_password.length > 1
          @password_users[hash[0]] = users_same_password
        end
        users_same_password = []
      end
  
    else
      # Used for Total Hashes Cracked doughnut: Customer
      @cracked_pw_count = repository(:default).adapter.select('SELECT count(h.plaintext) FROM hashes h LEFT JOIN hashfilehashes a on h.id = a.hash_id LEFT JOIN hashfiles f on a.hashfile_id = f.id WHERE (f.customer_id = ? AND h.cracked = 1)', params[:customer_id])[0].to_s
      @uncracked_pw_count = repository(:default).adapter.select('SELECT count(h.originalhash) FROM hashes h LEFT JOIN hashfilehashes a on h.id = a.hash_id LEFT JOIN hashfiles f on a.hashfile_id = f.id WHERE (f.customer_id = ? AND h.cracked = 0)', params[:customer_id])[0].to_s
  
      # Used for Total Accounts Table: Customer
      @total_accounts = @uncracked_pw_count.to_i + @cracked_pw_count.to_i

      # Used for Total Unique Users and original hashes Table: Customer
      @total_unique_users_count = repository(:default).adapter.select('SELECT COUNT(DISTINCT(username)) FROM hashfilehashes a LEFT JOIN hashfiles f ON a.hashfile_id = f.id WHERE f.customer_id = ?', params[:customer_id])[0].to_s
      @total_unique_originalhash_count = repository(:default).adapter.select('SELECT COUNT(DISTINCT(h.originalhash)) FROM hashes h LEFT JOIN hashfilehashes a ON h.id = a.hash_id LEFT JOIN hashfiles f ON a.hashfile_id = f.id WHERE f.customer_id = ?', params[:customer_id])[0].to_s
  
      # Used for Total Run Time: Customer:
      @total_run_time = Hashfiles.sum(:total_run_time, conditions: { :customer_id => params[:customer_id] })
    end
  else
    # Used for Total Hash Cracked Doughnut: Total
    @cracked_pw_count = Hashes.count(cracked: 1)
    @uncracked_pw_count = Hashes.count(cracked: 0)
 
    # Used for Total Accounts Table: Total
    @total_accounts = Hashfilehashes.count
  
    # Used for Total Unique Users and originalhashes Tables: Total
    @total_unique_users_count = repository(:default).adapter.select('SELECT COUNT(DISTINCT(username)) FROM hashfilehashes')[0].to_s
    @total_unique_originalhash_count = repository(:default).adapter.select('SELECT COUNT(DISTINCT(originalhash)) FROM hashes')[0].to_s
  
    # Used for Total Run Time:
    @total_run_time = Hashfiles.sum(:total_run_time)
  end
  
  @passwords = @cracked_results.to_json
  
  haml :analytics
end
  
# callback for d3 graph displaying passwords by length
get '/analytics/graph1' do
  varWash(params)
  
  @counts = []
  @passwords = {}
  
  if params[:customer_id] && !params[:customer_id].empty?
    if params[:hashfile_id] && !params[:hashfile_id].empty?
      @cracked_results = repository(:default).adapter.select('SELECT h.plaintext FROM hashes h LEFT JOIN hashfilehashes a ON h.id = a.hash_id WHERE h.cracked = 1 AND a.hashfile_id = ?', params[:hashfile_id])
    else
      @cracked_results = repository(:default).adapter.select('SELECT h.plaintext FROM hashes h LEFT JOIN hashfilehashes a ON h.id = a.hash_id LEFT JOIN hashfiles f on a.hashfile_id = f.id WHERE h.cracked = 1 AND f.customer_id = ?', params[:customer_id])
    end
  else
    @cracked_results = repository(:default).adapter.select('SELECT plaintext FROM hashes WHERE cracked = 1')
  end
  
  @cracked_results.each do |crack|
    unless crack.nil?
      unless crack.length == 0
        len = crack.length
        if @passwords[len].nil?
          @passwords[len] = 1
        else
          @passwords[len] = @passwords[len].to_i + 1
        end
      end
    end
  end
 
  # Sort on key
  @passwords = @passwords.sort.to_h
  
  # convert to array of json objects for d3
  @passwords.each do |key, value|
    @counts << { length: key, count: value }
  end
  
  return @counts.to_json
end
  
# callback for d3 graph displaying top 10 passwords
get '/analytics/graph2' do
  varWash(params)
  
  # This could probably be replaced with: SELECT COUNT(a.hash_id) AS frq, h.plaintext FROM hashfilehashes a LEFT JOIN hashes h ON h.id =  a.hash_id WHERE h.cracked = '1' GROUP BY a.hash_id ORDER BY frq DESC LIMIT 10;
  
  plaintext = []
  if params[:customer_id] && !params[:customer_id].empty?
    if params[:hashfile_id] && !params[:hashfile_id].empty?
      @cracked_results = repository(:default).adapter.select('SELECT h.plaintext FROM hashes h LEFT JOIN hashfilehashes a ON h.id = a.hash_id WHERE h.cracked = 1 AND a.hashfile_id = ?', params[:hashfile_id])
    else
      @cracked_results = repository(:default).adapter.select('SELECT h.plaintext FROM hashes h LEFT JOIN hashfilehashes a ON h.id = a.hash_id LEFT JOIN hashfiles f on a.hashfile_id = f.id WHERE h.cracked = 1 AND f.customer_id = ?', params[:customer_id])
    end
  else
    @cracked_results = repository(:default).adapter.select('SELECT h.plaintext FROM hashes h LEFT JOIN hashfilehashes a ON h.id = a.hash_id WHERE h.cracked = 1')
  end
  
  @cracked_results.each do |crack|
    unless crack.nil?
      plaintext << crack unless crack.empty?
    end
  end
  
  @toppasswords = []
  @top10passwords = {}
  # get top 10 passwords
  plaintext.each do |pass|
    if @top10passwords[pass].nil?
      @top10passwords[pass] = 1
    else
      @top10passwords[pass] += 1
    end
  end
  
  # sort and convert to array of json objects for d3
  @top10passwords = @top10passwords.sort_by { |_key, value| value }.reverse.to_h
  # we only need top 10
  @top10passwords = Hash[@top10passwords.sort_by { |_k, v| -v }[0..9]]
  # convert to array of json objects for d3
  @top10passwords.each do |key, value|
    @toppasswords << { password: key, count: value }
  end
  
  return @toppasswords.to_json
end
  
# callback for d3 graph displaying top 10 base words
get '/analytics/graph3' do
  varWash(params)

  plaintext = []
  if params[:customer_id] && !params[:customer_id].empty?
    if params[:hashfile_id] && !params[:hashfile_id].empty?
      @cracked_results = repository(:default).adapter.select('SELECT h.plaintext FROM hashes h LEFT JOIN hashfilehashes a ON h.id = a.hash_id WHERE h.cracked = 1 AND a.hashfile_id = ?', params[:hashfile_id])
    else
      @cracked_results = repository(:default).adapter.select('SELECT h.plaintext FROM hashes h LEFT JOIN hashfilehashes a ON h.id = a.hash_id LEFT JOIN hashfiles f on a.hashfile_id = f.id WHERE h.cracked = 1 AND f.customer_id = ?', params[:customer_id])
    end
  else
    @cracked_results = repository(:default).adapter.select('SELECT h.plaintext FROM hashes h LEFT JOIN hashfilehashes a ON h.id = a.hash_id WHERE h.cracked = 1')
  end
  @cracked_results.each do |crack|
    unless crack.nil?
      plaintext << crack unless crack.empty?
    end
  end
  
  @topbasewords = []
  @top10basewords = {}
  # get top 10 basewords
  plaintext.each do |pass|
    word_just_alpha = pass.gsub(/^[^a-z]*/i, '').gsub(/[^a-z]*$/i, '')
    unless word_just_alpha.nil? or word_just_alpha.empty?
      if @top10basewords[word_just_alpha].nil?
        @top10basewords[word_just_alpha] = 1
      else
        @top10basewords[word_just_alpha] += 1
      end
    end
  end
  
  # sort and convert to array of json objects for d3
  @top10basewords = @top10basewords.sort_by { |_key, value| value }.reverse.to_h
  # we only need top 10
  @top10basewords = Hash[@top10basewords.sort_by { |_k, v| -v }[0..9]]
  # convert to array of json objects for d3
  @top10basewords.each do |key, value|
    @topbasewords << { password: key, count: value }
  end
  
  return @topbasewords.to_json
end
