require 'json'

# displays analytics for a specific client, job
get '/analytics' do

  varWash(params)

  @customer_id = params[:customer_id]
  @hashfile_id = params[:hashfile_id]
  @button_select_customers = Customers.order(Sequel.asc(:name)).all

  if params[:customer_id] && !params[:customer_id].empty?
    @button_select_hashfiles = Hashfiles.where(customer_id: params[:customer_id]).all
  end

  if params[:customer_id] && !params[:customer_id].empty?
    @customers = Customers.first(id: params[:customer_id])
  else
    @customers = Customers.order(Sequel.asc(:name)).all
  end

  if params[:customer_id] && !params[:customer_id].empty?
    if params[:hashfile_id] && !params[:hashfile_id].empty?
      @hashfiles = Hashfiles.first(id: params[:hashfile_id])
    else
      @hashfiles = Hashfiles.order(Sequel.asc(:id)).all
    end
  end

  # get results of specific customer if customer_id is defined
  # if we have a customer
  if params[:customer_id] && !params[:customer_id].empty?
    # if we have a hashfile
    if params[:hashfile_id] && !params[:hashfile_id].empty?
      # Used for Complexity Breakdown doughnut: Customer: Hashfile
      @complexity_hashes = HVDB.fetch('SELECT a.username as username, h.plaintext as plaintext FROM hashes h LEFT JOIN hashfilehashes a ON h.id = a.hash_id WHERE (a.hashfile_id = ? AND h.cracked = 1)', params[:hashfile_id])
      @cracked_pw_count = HVDB.fetch('SELECT COUNT(h.originalhash) as count FROM hashes h LEFT JOIN hashfilehashes a ON h.id = a.hash_id WHERE (a.hashfile_id = ? AND h.cracked = 1)', params[:hashfile_id])[:count]
      @cracked_pw_count = @cracked_pw_count[:count]

      # Used for Total Accounts table: Customer: Hashfile
      @total_accounts = @uncracked_pw_count.to_i + @cracked_pw_count.to_i

      # Used for Total Unique Users and originalhashes Table: Customer: Hashfile
      @total_users_originalhash = HVDB.fetch('SELECT a.username, h.originalhash FROM hashes h LEFT JOIN hashfilehashes a ON h.id = a.hash_id LEFT JOIN hashfiles f on a.hashfile_id = f.id WHERE (f.customer_id = ? AND f.id = ?)', params[:customer_id],params[:hashfile_id])

      @total_unique_users_count = HVDB.fetch('SELECT COUNT(DISTINCT(username)) as count FROM hashfilehashes WHERE hashfile_id = ?', params[:hashfile_id])[:count]
      @total_unique_users_count = @total_unique_users_count[:count]
      @total_unique_originalhash_count = HVDB.fetch('SELECT COUNT(DISTINCT(h.originalhash)) as count FROM hashes h LEFT JOIN hashfilehashes a ON h.id = a.hash_id WHERE a.hashfile_id = ?', params[:hashfile_id])[:count]
      @total_unique_originalhash_count = @total_unique_originalhash_count[:count]

      # Used for Total Run Time: Customer: Hashfile
      @total_run_time = Hashfiles.first(id: params[:hashfile_id])[:total_run_time]

      # Used for Mask Generator: Customer: Hashfile
      @hashes_for_mask = HVDB.fetch('SELECT h.plaintext as plaintext FROM hashes h LEFT JOIN hashfilehashes a ON h.id = a.hash_id WHERE (a.hashfile_id = ? AND h.cracked = 1)', params[:hashfile_id])

      # make list of unique hashes
      unique_hashes = Set.new
      @total_users_originalhash.each do |entry|
        unique_hashes.add(entry[:originalhash])
      end

      hashes = []
      # create array of all hashes to count dups
      @total_users_originalhash.each do |uh|
        unless uh[:originalhash].nil?
          hashes << uh[:originalhash] unless uh[:originalhash].empty?
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
        dups = HVDB.fetch('SELECT a.username, h.plaintext, h.cracked FROM hashes h LEFT JOIN hashfilehashes a on h.id = a.hash_id LEFT JOIN hashfiles f on a.hashfile_id = f.id WHERE (f.customer_id =? AND f.id = ? AND h.originalhash = ?)', params[:customer_id], params[:hashfile_id], hash[0] )
        # for each user with the same password hash add user to array
        dups.each do |d|
          if !d[:username].nil?
            users_same_password << d[:username]
          else
            users_same_password << 'NULL'
          end
          if d[:cracked]
            hash[0] = d[:plaintext]
          end
        end
        # assign array of users to hash of similar password hashes
        if users_same_password.length > 1
          @password_users[hash[0]] = users_same_password
        end
        users_same_password = []
      end

    else

      # Used for Complexity Breakdown doughnut: Customer
      @complexity_hashes = HVDB.fetch('SELECT a.username, h.plaintext FROM hashes h LEFT JOIN hashfilehashes a on h.id = a.hash_id LEFT JOIN hashfiles f on a.hashfile_id = f.id WHERE (f.customer_id = ? AND h.cracked = 1)', params[:customer_id])
      @cracked_pw_count = HVDB.fetch('SELECT count(h.plaintext) as count FROM hashes h LEFT JOIN hashfilehashes a on h.id = a.hash_id LEFT JOIN hashfiles f on a.hashfile_id = f.id WHERE (f.customer_id = ? AND h.cracked = 1)', params[:customer_id])[:count]
      @cracked_pw_count = @cracked_pw_count[:count]

      # Used for Total Accounts Table: Customer
      @total_accounts = @uncracked_pw_count.to_i + @cracked_pw_count.to_i

      # Used for Total Unique Users and original hashes Table: Customer
      @total_unique_users_count = HVDB.fetch('SELECT COUNT(DISTINCT(username)) as count FROM hashfilehashes a LEFT JOIN hashfiles f ON a.hashfile_id = f.id WHERE f.customer_id = ?', params[:customer_id])[:count]
      @total_unique_users_count = @total_unique_users_count[:count]
      @total_unique_originalhash_count = HVDB.fetch('SELECT COUNT(DISTINCT(h.originalhash)) as count FROM hashes h LEFT JOIN hashfilehashes a ON h.id = a.hash_id LEFT JOIN hashfiles f ON a.hashfile_id = f.id WHERE f.customer_id = ?', params[:customer_id])[:count]
      @total_unique_originalhash_count = @total_unique_originalhash_count[:count]

      # Used for Total Run Time: Customer:
      @total_run_time = Hashfiles.where(:customer_id => params[:customer_id]).sum(:total_run_time)

      # Used for Mask Generator: Customer: Hashfile
      @hashes_for_mask = HVDB.fetch('SELECT h.plaintext FROM hashes h LEFT JOIN hashfilehashes a on h.id = a.hash_id LEFT JOIN hashfiles f on a.hashfile_id = f.id WHERE (f.customer_id = ? AND h.cracked = 1)', params[:customer_id])

    end
  else

    # Used for Complexity Breakdown Doughnut: Total
    @complexity_hashes = HVDB.fetch('SELECT a.username, h.plaintext FROM hashes h LEFT JOIN hashfilehashes a on h.id = a.hash_id LEFT JOIN hashfiles f on a.hashfile_id = f.id WHERE (h.cracked = 1)')
    @cracked_pw_count = HVDB.fetch('SELECT COUNT(h.originalhash) as count FROM hashes h LEFT JOIN hashfilehashes a ON h.id = a.hash_id WHERE (h.cracked = 1)')[:count]
    @cracked_pw_count = @cracked_pw_count[:count]

    # Used for Total Accounts Table: Total
    @total_accounts = Hashfilehashes.count

    # Used for Total Unique Users and originalhashes Tables: Total
    @total_unique_users_count = HVDB.fetch('SELECT COUNT(DISTINCT(username)) as count FROM hashfilehashes')[:count]
    @total_unique_users_count = @total_unique_users_count[:count]
    @total_unique_originalhash_count = HVDB.fetch('SELECT COUNT(DISTINCT(originalhash)) as count FROM hashes')[:count]
    @total_unique_originalhash_count = @total_unique_originalhash_count[:count]

    # Used for Total Run Time:
    @total_run_time = Hashfiles.sum(:total_run_time)

    # Used for Mask Generator: Customer: Hashfile
    @hashes_for_mask = HVDB.fetch('SELECT h.plaintext as plaintext FROM hashes h LEFT JOIN hashfilehashes a on h.id = a.hash_id LEFT JOIN hashfiles f on a.hashfile_id = f.id WHERE (h.cracked = 1)')

  end

  # Parse Complexity variables
  @meets_complexity_count = 0
  @fails_complexity_count = 0
  @fails_complexity = {}
  @complexity_hashes.each do |entry|
    if entry[:plaintext].to_s.length < 6
      @fails_complexity[entry[:username]] = entry[:plaintext]
    else
      flags = 0
      flags += 1 if entry[:plaintext].to_s =~ /[a-z]/
      flags += 1 if entry[:plaintext].to_s =~ /[A-Z]/
      flags += 1 if entry[:plaintext].to_s =~ /\d/
      flags += 1 if entry[:plaintext].to_s.force_encoding('UTF-8') =~ /[^0-9A-Za-z]/u
      @fails_complexity[entry[:username]] = entry[:plaintext] if flags < 3
    end
    @fails_complexity_count = @fails_complexity.length
    @meets_complexity_count = @cracked_pw_count.to_i - @fails_complexity_count.to_i
  end

  # Mask Coposition variables
  @mask_list = {}
  @hashes_for_mask.each do |entry|
    entry = entry[:plaintext]
    entry = entry.gsub(/[A-Z]/, 'U') # Find all upper case chars
    entry = entry.gsub(/[a-z]/, 'L') # Find all lower case chars
    entry = entry.gsub(/[0-9]/, 'D') # Find all digits
    entry = entry.force_encoding('UTF-8').gsub(/[^0-9A-Za-z]/u, 'S')
    if @mask_list[entry].nil?
      @mask_list[entry] = 0
    else
      @mask_list[entry] += 1
    end
  end

  @top_ten_masks = []
  top_ten_entry = {}
  total = 0
  percent_total = 0

  @mask_list = @mask_list.sort_by { |_key, value| -value }[0..9]
  @mask_list.each do |key, value|
    key = key.gsub(/U/, '?u')
    key = key.gsub(/L/, '?l')
    key = key.gsub(/D/, '?d')
    key = key.gsub(/S/, '?s')
    value = value + 1
    top_ten_entry[:mask] = key
    top_ten_entry[:count] = value
    total += value
    top_ten_entry[:percentage] = ((value.to_f / @cracked_pw_count.to_f) * 100)
    percent_total += ((value.to_f / @cracked_pw_count.to_f) * 100)
    @top_ten_masks.push(top_ten_entry)
    top_ten_entry = {}
  end
  top_ten_entry[:mask] = 'OTHER'
  top_ten_entry[:count] = @cracked_pw_count - total
  top_ten_entry[:percentage] = (100 - percent_total).to_s
  @top_ten_masks.push(top_ten_entry)

  @passwords = @cracked_results.to_json

  haml :analytics
end

# Callback for d3 graph for displaying Total Hashes Cracked
get '/analytics/graph/TotalHashesCracked' do

  varWash(params)

  if params[:customer_id] && !params[:customer_id].empty?
    # if we have a hashfile
    if params[:hashfile_id] && !params[:hashfile_id].empty?
      # Used for Total Hashes Cracked doughnut: Customer: Hashfile

      @cracked_pw_count = HVDB.fetch('SELECT COUNT(h.originalhash) as count FROM hashes h LEFT JOIN hashfilehashes a ON h.id = a.hash_id WHERE (a.hashfile_id = ? AND h.cracked = 1)', params[:hashfile_id])[:count]
      @cracked_pw_count = @cracked_pw_count[:count]
      @uncracked_pw_count = HVDB.fetch('SELECT COUNT(h.originalhash) as count FROM hashes h LEFT JOIN hashfilehashes a ON h.id = a.hash_id WHERE (a.hashfile_id = ? AND h.cracked = 0)', params[:hashfile_id])[:count]
      @uncracked_pw_count = @uncracked_pw_count[:count]
    else
      # Used for Total Hashes Cracked doughnut: Customer
      @cracked_pw_count = HVDB.fetch('SELECT count(h.plaintext) as count FROM hashes h LEFT JOIN hashfilehashes a on h.id = a.hash_id LEFT JOIN hashfiles f on a.hashfile_id = f.id WHERE (f.customer_id = ? AND h.cracked = 1)', params[:customer_id])[:count]
      @cracked_pw_count = @cracked_pw_count[:count]
      @uncracked_pw_count = HVDB.fetch('SELECT count(h.originalhash) as count FROM hashes h LEFT JOIN hashfilehashes a on h.id = a.hash_id LEFT JOIN hashfiles f on a.hashfile_id = f.id WHERE (f.customer_id = ? AND h.cracked = 0)', params[:customer_id])[:count]
      @uncracked_pw_count = @uncracked_pw_count[:count]
    end
  else
    # Used for Total Hash Cracked Doughnut: Total
    @cracked_pw_count = HVDB.fetch('SELECT COUNT(h.originalhash) as count FROM hashes h LEFT JOIN hashfilehashes a ON h.id = a.hash_id WHERE (h.cracked = 1)')[:count]
    @cracked_pw_count = @cracked_pw_count[:count]
    @uncracked_pw_count = HVDB.fetch('SELECT COUNT(h.originalhash) as count FROM hashes h LEFT JOIN hashfilehashes a ON h.id = a.hash_id WHERE (h.cracked = 0)')[:count]
    @uncracked_pw_count = @uncracked_pw_count[:count]
  end

  content = []
  content << { 'label':'Cracked', 'value':@cracked_pw_count }
  content << { 'label':'Uncracked', 'value':@uncracked_pw_count }
  return content.to_json
end

# Callback for d3 graph for displaying Complexity Breakdown
get '/analytics/graph/ComplexityBreakdown' do

  varWash(params)

  if params[:customer_id] && !params[:customer_id].empty?
    # if we have a hashfile
    if params[:hashfile_id] && !params[:hashfile_id].empty?
      # Used for Complexity Breakdown doughnut: Customer: Hashfile
      @complexity_hashes = HVDB.fetch('SELECT a.username as username, h.plaintext as plaintext FROM hashes h LEFT JOIN hashfilehashes a ON h.id = a.hash_id WHERE (a.hashfile_id = ? AND h.cracked = 1)', params[:hashfile_id])
      @cracked_pw_count = HVDB.fetch('SELECT COUNT(h.originalhash) as count FROM hashes h LEFT JOIN hashfilehashes a ON h.id = a.hash_id WHERE (a.hashfile_id = ? AND h.cracked = 1)', params[:hashfile_id])[:count]
      @cracked_pw_count = @cracked_pw_count[:count]
    else
      # Used for Complexity Breakdown doughnut: Customer
      @complexity_hashes = HVDB.fetch('SELECT a.username, h.plaintext FROM hashes h LEFT JOIN hashfilehashes a on h.id = a.hash_id LEFT JOIN hashfiles f on a.hashfile_id = f.id WHERE (f.customer_id = ? AND h.cracked = 1)', params[:customer_id])
      @cracked_pw_count = HVDB.fetch('SELECT count(h.plaintext) as count FROM hashes h LEFT JOIN hashfilehashes a on h.id = a.hash_id LEFT JOIN hashfiles f on a.hashfile_id = f.id WHERE (f.customer_id = ? AND h.cracked = 1)', params[:customer_id])[:count]
      @cracked_pw_count = @cracked_pw_count[:count]
    end
  else
    # Used for Complexity Breakdown Doughnut: Total
    @complexity_hashes = HVDB.fetch('SELECT a.username, h.plaintext FROM hashes h LEFT JOIN hashfilehashes a on h.id = a.hash_id LEFT JOIN hashfiles f on a.hashfile_id = f.id WHERE (h.cracked = 1)')
    @cracked_pw_count = HVDB.fetch('SELECT COUNT(h.originalhash) as count FROM hashes h LEFT JOIN hashfilehashes a ON h.id = a.hash_id WHERE (h.cracked = 1)')[:count]
    @cracked_pw_count = @cracked_pw_count[:count]
  end

  @meets_complexity_count = 0
  @fails_complexity_count = 0
  @fails_complexity = {}
  @complexity_hashes.each do |entry|
    if entry[:plaintext].to_s.length < 6
      @fails_complexity[entry[:username]] = entry[:plaintext]
    else
      flags = 0
      flags += 1 if entry[:plaintext].to_s =~ /[a-z]/
      flags += 1 if entry[:plaintext].to_s =~ /[A-Z]/
      flags += 1 if entry[:plaintext].to_s =~ /\d/
      flags += 1 if entry[:plaintext].to_s.force_encoding('UTF-8') =~ /[^0-9A-Za-z]/u
      @fails_complexity[entry[:username]] = entry[:plaintext] if flags < 3
    end
    @fails_complexity_count = @fails_complexity.length
    @meets_complexity_count = @cracked_pw_count.to_i - @fails_complexity_count.to_i
  end

  content = []
  content << { 'label':'Fails Complexity', 'value':@fails_complexity_count }
  content << { 'label':'Meets Complexity', 'value':@meets_complexity_count }
  return content.to_json
end

# Callback for d3 graph for displaying Complexity Breakdown
get '/analytics/graph/CharsetBreakdown' do

  varWash(params)

  if params[:customer_id] && !params[:customer_id].empty?
    # if we have a hashfile
    if params[:hashfile_id] && !params[:hashfile_id].empty?
      # Used for Complexity Breakdown doughnut: Customer: Hashfile
      @complexity_hashes = HVDB.fetch('SELECT a.username as username, h.plaintext as plaintext FROM hashes h LEFT JOIN hashfilehashes a ON h.id = a.hash_id WHERE (a.hashfile_id = ? AND h.cracked = 1)', params[:hashfile_id])
      @cracked_pw_count = HVDB.fetch('SELECT COUNT(h.originalhash) as count FROM hashes h LEFT JOIN hashfilehashes a ON h.id = a.hash_id WHERE (a.hashfile_id = ? AND h.cracked = 1)', params[:hashfile_id])[:count]
      cracked_pw_count = @cracked_pw_count[:count]
    else
      # Used for Complexity Breakdown doughnut: Customer
      @complexity_hashes = HVDB.fetch('SELECT a.username, h.plaintext FROM hashes h LEFT JOIN hashfilehashes a on h.id = a.hash_id LEFT JOIN hashfiles f on a.hashfile_id = f.id WHERE (f.customer_id = ? AND h.cracked = 1)', params[:customer_id])
      @cracked_pw_count = HVDB.fetch('SELECT count(h.plaintext) as count FROM hashes h LEFT JOIN hashfilehashes a on h.id = a.hash_id LEFT JOIN hashfiles f on a.hashfile_id = f.id WHERE (f.customer_id = ? AND h.cracked = 1)', params[:customer_id])[:count]
      cracked_pw_count = @cracked_pw_count[:count]
    end
  else
    # Used for Complexity Breakdown Doughnut: Total
    @complexity_hashes = HVDB.fetch('SELECT a.username, h.plaintext FROM hashes h LEFT JOIN hashfilehashes a on h.id = a.hash_id LEFT JOIN hashfiles f on a.hashfile_id = f.id WHERE (h.cracked = 1)')
    @cracked_pw_count = HVDB.fetch('SELECT COUNT(h.originalhash) as count FROM hashes h LEFT JOIN hashfilehashes a ON h.id = a.hash_id WHERE (h.cracked = 1)')[:count]
    cracked_pw_count = @cracked_pw_count[:count]
  end

  numeric = 0
  loweralpha = 0
  upperalpha = 0
  special = 0

  mixedalpha = 0
  loweralphanum = 0
  upperalphanum = 0
  loweralphaspecial = 0
  upperalphaspecial = 0
  specialnum = 0

  mixedalphaspecial = 0
  upperalphaspecialnum = 0
  loweralphaspecialnum = 0
  mixedalphanum = 0

  other = 0

  @fails_complexity = {}
  @complexity_hashes.each do |entry|
    entry = entry[:plaintext]
    entry = entry.gsub(/[A-Z]/, 'U') # Find all upper case chars
    entry = entry.gsub(/[a-z]/, 'L') # Find all lower case chars
    entry = entry.gsub(/[0-9]/, 'D') # Find all digits
    entry = entry.force_encoding('UTF-8').gsub(/[^0-9A-Za-z]/u, 'S')

    if entry !~ /U/ && entry !~ /L/ && entry =~ /D/ && entry !~ /S/
      numeric += 1
    elsif entry !~ /U/ && entry =~ /L/ && entry !~ /D/ && entry !~ /S/
      loweralpha += 1
    elsif entry =~ /U/ && entry !~ /L/ && entry !~ /D/ && entry !~ /S/
      upperalpha += 1
    elsif entry !~ /U/ && entry !~ /L/ && entry !~ /D/ && entry =~ /S/
      special += 1
    elsif entry =~ /U/ && entry =~ /L/ && entry !~ /D/ && entry !~ /S/
      mixedalpha += 1
    elsif entry =~ /U/ && entry !~ /L/ && entry =~ /D/ && entry !~ /S/
      loweralphanum += 1
    elsif entry =~ /U/ && entry =~ /L/ && entry =~ /D/ && entry !~ /S/
      upperalphanum += 1
    elsif entry !~ /U/ && entry =~ /L/ && entry !~ /D/ && entry =~ /S/
      loweralphaspecial += 1
    elsif entry =~ /U/ && entry !~ /L/ && entry !~ /D/ && entry =~ /S/
      upperalphaspecial += 1
    elsif entry !~ /U/ && entry !~ /L/ && entry =~ /D/ && entry =~ /S/
      specialnum += 1
    elsif entry =~ /U/ && entry =~ /L/ && entry !~ /D/ && entry =~ /S/
      mixedalphaspecial += 1
    elsif entry =~ /U/ && entry !~ /L/ && entry =~ /D/ && entry =~ /S/
      upperalphaspecialnum += 1
    elsif entry !~ /U/ && entry =~ /L/ && entry =~ /D/ && entry =~ /S/
      loweralphaspecialnum += 1
    elsif entry =~ /U/ && entry =~ /L/ && entry =~ /D/ && entry =~ /S/
      mixedalphanum += 1
    else
      other += 1
    end
  end

  charset_list = {}
  charset_list[:numeric] = numeric
  charset_list[:loweralpha] = loweralpha
  charset_list[:upperalpha] = upperalpha
  charset_list[:special] = special
  charset_list[:mixedalpha] = mixedalpha
  charset_list[:loweralphanum] = loweralphanum
  charset_list[:upperalphanum] = upperalphanum
  charset_list[:loweralphaspecial] = loweralphaspecial
  charset_list[:upperalphaspecial] = upperalphaspecial
  charset_list[:specialnum] = specialnum
  charset_list[:mixedalphaspecial] = mixedalphaspecial
  charset_list[:upperalphaspecialnum] = upperalphaspecialnum
  charset_list[:loweralphaspecialnum] = loweralphaspecialnum
  charset_list[:mixedalphanum] = mixedalphanum

  content = []
  charset_list = charset_list.sort_by { |_key, value| -value }[0..5]
  charset_list.each do |key, value|
    content << { 'label':key, 'value':value } if value > 0
  end

  return content.to_json
end

# callback for d3 graph displaying passwords by length
get '/analytics/PasswordsCountByLength' do

  varWash(params)

  @counts = []
  @passwords = {}

  if params[:customer_id] && !params[:customer_id].empty?
    if params[:hashfile_id] && !params[:hashfile_id].empty?
      @cracked_results = HVDB.fetch('SELECT h.plaintext FROM hashes h LEFT JOIN hashfilehashes a ON h.id = a.hash_id WHERE h.cracked = 1 AND a.hashfile_id = ?', params[:hashfile_id])
    else
      @cracked_results = HVDB.fetch('SELECT h.plaintext FROM hashes h LEFT JOIN hashfilehashes a ON h.id = a.hash_id LEFT JOIN hashfiles f on a.hashfile_id = f.id WHERE h.cracked = 1 AND f.customer_id = ?', params[:customer_id])
    end
  else
    @cracked_results = HVDB.fetch('SELECT plaintext FROM hashes WHERE cracked = 1')
  end

  @cracked_results.each do |crack|
    unless crack[:plaintext].nil?
      unless crack[:plaintext].empty?
        len = crack[:plaintext].length
        @passwords[len].nil? ? @passwords[len] = 1 : @passwords[len] = @passwords[len].to_i + 1
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
get '/analytics/Top10Passwords' do

  varWash(params)

  # This could probably be replaced with: SELECT COUNT(a.hash_id) AS frq, h.plaintext FROM hashfilehashes a LEFT JOIN hashes h ON h.id =  a.hash_id WHERE h.cracked = '1' GROUP BY a.hash_id ORDER BY frq DESC LIMIT 10;

  plaintext = []
  if params[:customer_id] && !params[:customer_id].empty?
    if params[:hashfile_id] && !params[:hashfile_id].empty?
      @cracked_results = HVDB.fetch('SELECT h.plaintext FROM hashes h LEFT JOIN hashfilehashes a ON h.id = a.hash_id WHERE h.cracked = 1 AND a.hashfile_id = ?', params[:hashfile_id])
    else
      @cracked_results = HVDB.fetch('SELECT h.plaintext FROM hashes h LEFT JOIN hashfilehashes a ON h.id = a.hash_id LEFT JOIN hashfiles f on a.hashfile_id = f.id WHERE h.cracked = 1 AND f.customer_id = ?', params[:customer_id])
    end
  else
    @cracked_results = HVDB.fetch('SELECT h.plaintext FROM hashes h LEFT JOIN hashfilehashes a ON h.id = a.hash_id WHERE h.cracked = 1')
  end

  @cracked_results.each do |crack|
    unless crack[:plaintext].nil?
      plaintext << crack[:plaintext] unless crack[:plaintext].empty?
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
get '/analytics/Top10BaseWords' do

  varWash(params)

  plaintext = []
  if params[:customer_id] && !params[:customer_id].empty?
    if params[:hashfile_id] && !params[:hashfile_id].empty?
      @cracked_results = HVDB.fetch('SELECT h.plaintext FROM hashes h LEFT JOIN hashfilehashes a ON h.id = a.hash_id WHERE h.cracked = 1 AND a.hashfile_id = ?', params[:hashfile_id])
    else
      @cracked_results = HVDB.fetch('SELECT h.plaintext FROM hashes h LEFT JOIN hashfilehashes a ON h.id = a.hash_id LEFT JOIN hashfiles f on a.hashfile_id = f.id WHERE h.cracked = 1 AND f.customer_id = ?', params[:customer_id])
    end
  else
    @cracked_results = HVDB.fetch('SELECT h.plaintext FROM hashes h LEFT JOIN hashfilehashes a ON h.id = a.hash_id WHERE h.cracked = 1')
  end
  @cracked_results.each do |crack|
    unless crack[:plaintext].nil?
      plaintext << crack[:plaintext] unless crack[:plaintext].empty?
    end
  end

  @topbasewords = []
  @top10basewords = {}
  # get top 10 basewords
  plaintext.each do |pass|
    word_just_alpha = pass.gsub(/^[^a-z]*/i, '').gsub(/[^a-z]*$/i, '')
    unless word_just_alpha.nil? || word_just_alpha.empty?
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

# callback for Accounts with Weak Passwords
get '/analytics/AccountsWithWeakPasswords' do

  varWash(params)

  # TODO
  # complexity hashes and cracked pw count should be from a single query, not multiple.
  if params[:customer_id] && !params[:customer_id].empty?
    # if we have a hashfile
    if params[:hashfile_id] && !params[:hashfile_id].empty?
      # Used for Complexity Breakdown doughnut: Customer: Hashfile
      @complexity_hashes = HVDB.fetch('SELECT a.username as username, h.plaintext as plaintext FROM hashes h LEFT JOIN hashfilehashes a ON h.id = a.hash_id WHERE (a.hashfile_id = ? AND h.cracked = 1)', params[:hashfile_id])
      @cracked_pw_count = HVDB.fetch('SELECT COUNT(h.originalhash) as count FROM hashes h LEFT JOIN hashfilehashes a ON h.id = a.hash_id WHERE (a.hashfile_id = ? AND h.cracked = 1)', params[:hashfile_id])[:count]
      @cracked_pw_count = @cracked_pw_count[:count]
    else
      # Used for Complexity Breakdown doughnut: Customer
      @complexity_hashes = HVDB.fetch('SELECT a.username, h.plaintext FROM hashes h LEFT JOIN hashfilehashes a on h.id = a.hash_id LEFT JOIN hashfiles f on a.hashfile_id = f.id WHERE (f.customer_id = ? AND h.cracked = 1)', params[:customer_id])
      @cracked_pw_count = HVDB.fetch('SELECT count(h.plaintext) as count FROM hashes h LEFT JOIN hashfilehashes a on h.id = a.hash_id LEFT JOIN hashfiles f on a.hashfile_id = f.id WHERE (f.customer_id = ? AND h.cracked = 1)', params[:customer_id])[:count]
      @cracked_pw_count = @cracked_pw_count[:count]
    end
  else
    # Used for Complexity Breakdown Doughnut: Total
    @complexity_hashes = HVDB.fetch('SELECT a.username, h.plaintext FROM hashes h LEFT JOIN hashfilehashes a on h.id = a.hash_id LEFT JOIN hashfiles f on a.hashfile_id = f.id WHERE (h.cracked = 1)')
    @cracked_pw_count = HVDB.fetch('SELECT COUNT(h.originalhash) as count FROM hashes h LEFT JOIN hashfilehashes a ON h.id = a.hash_id WHERE (h.cracked = 1)')[:count]
    @cracked_pw_count = @cracked_pw_count[:count]
  end

  @meets_complexity_count = 0
  @fails_complexity_count = 0
  @fails_complexity = {}
  @complexity_hashes.each do |entry|
    if entry[:plaintext].to_s.length < 6
      @fails_complexity[entry[:username]] = entry[:plaintext]
    else
      flags = 0
      flags += 1 if entry[:plaintext].to_s =~ /[a-z]/
      flags += 1 if entry[:plaintext].to_s =~ /[A-Z]/
      flags += 1 if entry[:plaintext].to_s =~ /\d/
      flags += 1 if entry[:plaintext].to_s.force_encoding('UTF-8') =~ /[^0-9A-Za-z]/u
      @fails_complexity[entry[:username]] = entry[:plaintext] if flags < 3
    end
    @fails_complexity_count = @fails_complexity.length
    @meets_complexity_count = @cracked_pw_count.to_i - @fails_complexity_count.to_i
  end

  mass = []
  content = []
  content << { 'label':'Fails Complexity', 'value':'5' }
  content << { 'label':'Meets Complexity', 'value':'10' }
  data = {"content": content}
  mass << data
  return content.to_json
end