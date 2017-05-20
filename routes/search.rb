# encoding: utf-8
get '/search' do
  haml :search
end
  
post '/search' do
  varWash(params)
  @customers = Customers.all
  hub_settings = HubSettings.first

  if params[:value].nil? || params[:value].empty?
    flash[:error] = 'Please provide a search term'
    redirect to('/search')
  end

  @results = []
  results_entry = {}
  # We have duplication here that can be cleaned up

  if params[:search_type].to_s == 'password'
    @local_results = repository(:default).adapter.select("SELECT a.username, h.id, h.plaintext, h.cracked, h.originalhash, h.hashtype, c.name FROM hashes h LEFT JOIN hashfilehashes a on h.id = a.hash_id LEFT JOIN hashfiles f on a.hashfile_id = f.id LEFT JOIN customers c ON f.customer_id = c.id WHERE h.plaintext like '%" + params[:value] + "%'")

    if @local_results.nil? || @local_results.empty?
      results_entry['local_cracked'] = '0'
    else
      p 'WE HAVE LOCAL ENTRY'
      p 'LOCAL RESULTS: ' + @local_results.to_s
      @local_results.each do |local_entry|
        p 'Local Entry: ' + local_entry.to_s
        results_entry['id'] = local_entry.id
        results_entry['username'] = local_entry.username
        results_entry['plaintext'] = local_entry.plaintext
        results_entry['hashtype'] = local_entry.hashtype
        results_entry['originalhash'] = local_entry.originalhash
        results_entry['name'] = local_entry.name
        results_entry['local_cracked'] = '1' if local_entry.cracked
        results_entry['local_cracked'] = '0' unless local_entry.cracked

        if hub_settings.status == 'registered' && local_entry.originalhash
          hub_response = Hub.hashSearch(local_entry.originalhash)
          hub_response = JSON.parse(hub_response)
          if hub_response['status'] == '200' or hub_response['status'] == '404'
            results_entry['originalhash'] = hub_response['hash'] if hub_response['cracked'] == '1'
            results_entry['hashtype'] = hub_response['hashtype'] if hub_response['cracked'] == '1'
            results_entry['show_hub_results'] = '1'
            results_entry['hub_hash_id'] = hub_response['hash_id']
            results_entry['hub_cracked'] = '1' if hub_response['cracked'] == '1'
            results_entry['hub_cracked'] = '0' if hub_response['cracked'] == '0' || hub_response['cracked'].nil?
          else
            flash[:error] = 'Error: Unauthorized access to Hub. Please check settings and try again.'
          end
        else
          results_entry['hub_cracked'] = '0'
        end

        # We have to push this into an array of 1 because search results page is expecting an array (which is used when searching for usernames or plaintexts)
        @results.push(results_entry)
        results_entry = {}
      end
    end

    p 'results:' + @results.to_s

  elsif params[:search_type].to_s == 'username'
    @local_results = repository(:default).adapter.select("SELECT a.username, h.id, h.plaintext, h.cracked, h.originalhash, h.hashtype, c.name FROM hashes h LEFT JOIN hashfilehashes a on h.id = a.hash_id LEFT JOIN hashfiles f on a.hashfile_id = f.id LEFT JOIN customers c ON f.customer_id = c.id WHERE a.username like '%" + params[:value] + "%'")

    if @local_results.nil? || @local_results.empty?
      results_entry['local_cracked'] = '0'
    else
      p 'WE HAVE LOCAL ENTRY'
      p 'LOCAL RESULTS: ' + @local_results.to_s
      @local_results.each do |local_entry|
        p 'Local Entry: ' + local_entry.to_s
        results_entry['id'] = local_entry.id
        results_entry['username'] = local_entry.username
        results_entry['plaintext'] = local_entry.plaintext
        results_entry['hashtype'] = local_entry.hashtype
        results_entry['originalhash'] = local_entry.originalhash
        results_entry['name'] = local_entry.name
        results_entry['local_cracked'] = '1' if local_entry.cracked
        results_entry['local_cracked'] = '0' unless local_entry.cracked

        if hub_settings.status == 'registered' && local_entry.originalhash
          hub_response = Hub.hashSearch(local_entry.originalhash)
          hub_response = JSON.parse(hub_response)
          if hub_response['status'] == '200' or hub_response['status'] == '404'
            results_entry['originalhash'] = hub_response['hash'] if hub_response['cracked'] == '1'
            results_entry['hashtype'] = hub_response['hashtype'] if hub_response['cracked'] == '1'
            results_entry['show_hub_results'] = '1'
            results_entry['hub_hash_id'] = hub_response['hash_id']
            results_entry['hub_cracked'] = '1' if hub_response['cracked'] == '1'
            results_entry['hub_cracked'] = '0' if hub_response['cracked'] == '0' || hub_response['cracked'].nil?
          else
            flash[:error] = 'Error: Unauthorized access to Hub. Please check settings and try again.'
          end
        else
          results_entry['hub_cracked'] = '0'
        end

        # We have to push this into an array of 1 because search results page is expecting an array (which is used when searching for usernames or plaintexts)
        @results.push(results_entry)
        results_entry = {}
      end
    end

    p 'results:' + @results.to_s



  elsif params[:search_type] == 'hash'

    @local_results = repository(:default).adapter.select("SELECT a.username, h.id, h.plaintext, h.cracked, h.originalhash, h.hashtype, c.name FROM hashes h LEFT JOIN hashfilehashes a on h.id = a.hash_id LEFT JOIN hashfiles f on a.hashfile_id = f.id LEFT JOIN customers c ON f.customer_id = c.id WHERE h.originalhash like '%" + params[:value] + "%'")

    if @local_results.nil? || @local_results.empty?
      results_entry['local_cracked'] = '0'
    else
      p 'WE HAVE LOCAL ENTRY'
      p 'LOCAL RESULTS: ' + @local_results.to_s
      @local_results.each do |local_entry|
        p 'Local Entry: ' + local_entry.to_s
        results_entry['id'] = local_entry.id
        results_entry['username'] = local_entry.username
        results_entry['plaintext'] = local_entry.plaintext
        results_entry['hashtype'] = local_entry.hashtype
        results_entry['originalhash'] = local_entry.originalhash
        results_entry['name'] = local_entry.name
        results_entry['local_cracked'] = '1' if local_entry.cracked
        results_entry['local_cracked'] = '0' unless local_entry.cracked
      end
    end

    if hub_settings.status == 'registered'
      hub_response = Hub.hashSearch(params[:value])
      hub_response = JSON.parse(hub_response)
      if hub_response['status'] == '200' or hub_response['status'] == '404'
        results_entry['originalhash'] = hub_response['hash'] if hub_response['cracked'] == '1'
        results_entry['hashtype'] = hub_response['hashtype'] if hub_response['cracked'] == '1'
        results_entry['show_hub_results'] = '1'
        results_entry['hub_hash_id'] = hub_response['hash_id']
        results_entry['hub_cracked'] = '1' if hub_response['cracked'] == '1'
        results_entry['hub_cracked'] = '0' if hub_response['cracked'] == '0' || hub_response['cracked'].nil?
      else
        flash[:error] = 'Error: Unauthorized access to Hub. Please check settings and try again.'
      end
    end
    # We have to push this into an array of 1 because search results page is expecting an array (which is used when searching for usernames or plaintexts)
    @results.push(results_entry)
    p 'results:' + @results.to_s
  end



  haml :search_post
end
