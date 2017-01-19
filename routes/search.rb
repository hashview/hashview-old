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
    @results = repository(:default).adapter.select('SELECT a.username, h.plaintext, h.originalhash, h.hashtype, c.name FROM hashes h LEFT JOIN hashfilehashes a on h.id = a.hash_id LEFT JOIN hashfiles f on a.hashfile_id = f.id LEFT JOIN customers c ON f.customer_id = c.id WHERE h.plaintext like ?', params[:value])
  elsif params[:search_type].to_s == 'username'
    @results = repository(:default).adapter.select('SELECT a.username, h.plaintext, h.originalhash, h.hashtype, c.name FROM hashes h LEFT JOIN hashfilehashes a on h.id = a.hash_id LEFT JOIN hashfiles f on a.hashfile_id = f.id LEFT JOIN customers c ON f.customer_id = c.id WHERE a.username like ?', params[:value])
  elsif params[:search_type] == 'hash'
    @results = repository(:default).adapter.select('SELECT a.username, h.plaintext, h.originalhash, h.hashtype, c.name FROM hashes h LEFT JOIN hashfilehashes a on h.id = a.hash_id LEFT JOIN hashfiles f on a.hashfile_id = f.id LEFT JOIN customers c ON f.customer_id = c.id WHERE h.originalhash like ?', params[:value])
  end

  haml :search_post
end

