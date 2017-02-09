# encoding: utf-8
get '/hashfiles/list' do
  @customers = Customers.all(order: [:name.asc])
  @hashfiles = Hashfiles.all
  @cracked_status = Hash.new
  @hashfiles.each do |hashfile|
    hashfile_cracked_count = repository(:default).adapter.select('SELECT COUNT(h.originalhash) FROM hashes h LEFT JOIN hashfilehashes a ON h.id = a.hash_id WHERE (a.hashfile_id = ? AND h.cracked = 1)', hashfile.id)[0].to_s
    hashfile_total_count = repository(:default).adapter.select('SELECT COUNT(h.originalhash) FROM hashes h LEFT JOIN hashfilehashes a ON h.id = a.hash_id WHERE a.hashfile_id = ?', hashfile.id)[0].to_s
    @cracked_status[hashfile.id] = hashfile_cracked_count.to_s + "/" + hashfile_total_count.to_s
  end

  haml :hashfile_list
end

get '/hashfiles/delete' do
  varWash(params)
  
  #repository(:default).adapter.select('DELETE hashes FROM hashes LEFT JOIN hashfilehashes ON hashes.id = hashfilehashes.hash_id WHERE (hashfilehashes.hashfile_id = ? AND hashes.cracked = 0)', params[:hashfile_id])

  @hashfilehashes = Hashfilehashes.all(hashfile_id: params[:hashfile_id])
  @hashfilehashes.destroy unless @hashfilehashes.empty?

  Removing this as it deletes hashes for other hashfiles
  @hashfile = Hashfiles.first(id: params[:hashfile_id])
  @hashfile.destroy unless @hashfile.nil?

  flash[:success] = 'Successfuly removed hashfile.'

  redirect to('/hashfiles/list')
end

