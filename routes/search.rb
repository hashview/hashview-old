# encoding: utf-8
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

  if params[:search_type].to_s == 'password'
    @results = repository(:default).adapter.select("SELECT a.username, h.plaintext, h.originalhash, h.hashtype, c.name FROM hashes h LEFT JOIN hashfilehashes a on h.id = a.hash_id LEFT JOIN hashfiles f on a.hashfile_id = f.id LEFT JOIN customers c ON f.customer_id = c.id WHERE h.plaintext like '%" + params[:value] + "%'")
    @result_source = 'local'
  elsif params[:search_type].to_s == 'username'
    @results = repository(:default).adapter.select("SELECT a.username, h.plaintext, h.originalhash, h.hashtype, c.name FROM hashes h LEFT JOIN hashfilehashes a on h.id = a.hash_id LEFT JOIN hashfiles f on a.hashfile_id = f.id LEFT JOIN customers c ON f.customer_id = c.id WHERE a.username like '%" + params[:value] + "%'")
    @result_source = 'local'
  elsif params[:search_type] == 'hash'
    @results = repository(:default).adapter.select("SELECT a.username, h.plaintext, h.originalhash, h.hashtype, c.name FROM hashes h LEFT JOIN hashfilehashes a on h.id = a.hash_id LEFT JOIN hashfiles f on a.hashfile_id = f.id LEFT JOIN customers c ON f.customer_id = c.id WHERE h.originalhash like '%" + params[:value] + "%'")
    if @results.nil? or @results.empty? # we only want to run the query if its not found cracked locally
      hub_settings = HubSettings.first
      if hub_settings.enabled == true and hub_settings.status == 'registered'
        @hub_response = Hub.hashSearch(params[:value])
        @hub_response = JSON.parse(@hub_response)
        p 'hub_response ' + @hub_response.to_s
        if @hub_response['status'] == '200'
          if @hub_response['cracked'] == '1'
            @result_source = 'hub'
          else
            flash[:success] = 'No results found on Hub'
          end
        end
        if @hub_response['status'] == '403'
          flash[:error] = 'Error: Unauthorized access to Hub. Please check settings and try again.'
        end
      end
    else
      @result_source = 'local'
    end
  end

  haml :search_post
end

