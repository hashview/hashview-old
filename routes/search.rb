get '/search' do
  haml :search
end

post '/search' do
  varWash(params)

  @customers = Customers.all

  if params[:value].nil? || params[:value].empty?
    flash[:error] = 'Please provide a search term'
    redirect to('/search')
  end

  @results = []
  results_entry = {}
  # We have duplication here that can be cleaned up

  if params[:search_type].to_s == 'password'
    @local_results = HVDB.fetch("SELECT a.username, h.id, h.plaintext, h.cracked, h.originalhash, h.hashtype, c.name FROM hashes h LEFT JOIN hashfilehashes a on h.id = a.hash_id LEFT JOIN hashfiles f on a.hashfile_id = f.id LEFT JOIN customers c ON f.customer_id = c.id WHERE h.plaintext like '%" + params[:value] + "%'")

    unless @local_results.nil? || @local_results.empty?
      @local_results.each do |local_entry|
        results_entry['id'] = local_entry[:id]
        results_entry['username'] = local_entry[:username]
        results_entry['plaintext'] = local_entry[:plaintext]
        results_entry['hashtype'] = local_entry[:hashtype]
        results_entry['originalhash'] = local_entry[:originalhash]
        results_entry['name'] = local_entry[:name]

        # We have to push this into an array of 1 because search results page is expecting an array (which is used when searching for usernames or plaintexts)
        @results.push(results_entry)
        results_entry = {}
      end
    end

  elsif params[:search_type].to_s == 'username'
    @local_results = HVDB.fetch("SELECT a.username, h.id, h.plaintext, h.cracked, h.originalhash, h.hashtype, c.name FROM hashes h LEFT JOIN hashfilehashes a on h.id = a.hash_id LEFT JOIN hashfiles f on a.hashfile_id = f.id LEFT JOIN customers c ON f.customer_id = c.id WHERE a.username like '%" + params[:value] + "%'")

    unless @local_results.nil? || @local_results.empty?
      @local_results.each do |local_entry|
        results_entry['id'] = local_entry[:id]
        results_entry['username'] = local_entry[:username]
        results_entry['plaintext'] = local_entry[:plaintext]
        results_entry['hashtype'] = local_entry[:hashtype]
        results_entry['originalhash'] = local_entry[:originalhash]
        results_entry['name'] = local_entry[:name]

        # We have to push this into an array of 1 because search results page is expecting an array (which is used when searching for usernames or plaintexts)
        @results.push(results_entry)
        results_entry = {}
      end
    end

  elsif params[:search_type] == 'hash'

    @local_results = HVDB.fetch("SELECT a.username, h.id, h.plaintext, h.cracked, h.originalhash, h.hashtype, c.name FROM hashes h LEFT JOIN hashfilehashes a on h.id = a.hash_id LEFT JOIN hashfiles f on a.hashfile_id = f.id LEFT JOIN customers c ON f.customer_id = c.id WHERE h.originalhash like '%" + params[:value] + "%'")

    unless @local_results.nil? || @local_results.empty?
      @local_results.each do |local_entry|
        results_entry['id'] = local_entry[:id]
        results_entry['username'] = local_entry[:username]
        results_entry['plaintext'] = local_entry[:plaintext]
        results_entry['hashtype'] = local_entry[:hashtype]
        results_entry['originalhash'] = local_entry[:originalhash]
        results_entry['name'] = local_entry[:name]
      end
    end

    # We have to push this into an array of 1 because search results page is expecting an array (which is used when searching for usernames or plaintexts)
    @results.push(results_entry)
  end

  haml :search_post
end
