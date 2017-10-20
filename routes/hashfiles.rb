# encoding: utf-8
get '/hashfiles/list' do
  @hub_settings = HubSettings.first
  @customers = Customers.all(order: [:name.asc])
  @hashfiles = Hashfiles.all
  @cracked_status = {}
  @local_cracked_cnt = {}
  @local_uncracked_cnt = {}

  @hashfiles.each do |hashfile|
    hashfile_cracked_count = repository(:default).adapter.select('SELECT COUNT(h.originalhash) FROM hashes h LEFT JOIN hashfilehashes a ON h.id = a.hash_id WHERE (a.hashfile_id = ? AND h.cracked = 1)', hashfile.id)[0].to_s
    hashfile_total_count = repository(:default).adapter.select('SELECT COUNT(h.originalhash) FROM hashes h LEFT JOIN hashfilehashes a ON h.id = a.hash_id WHERE a.hashfile_id = ?', hashfile.id)[0].to_s
    @local_cracked_cnt[hashfile.id] = hashfile_cracked_count.to_s
    @local_uncracked_cnt[hashfile.id] = hashfile_total_count.to_i - hashfile_cracked_count.to_i
    @cracked_status[hashfile.id] = hashfile_cracked_count.to_s + '/' + hashfile_total_count.to_s
  end

  haml :hashfile_list
end

get '/hashfiles/delete' do
  varWash(params)

  @hashfilehashes = Hashfilehashes.all(hashfile_id: params[:hashfile_id])
  @hashfilehashes.destroy unless @hashfilehashes.empty?

  @hashfile = Hashfiles.first(id: params[:hashfile_id])
  @hashfile.destroy unless @hashfile.nil?

  flash[:success] = 'Successfully removed hashfile.'

  redirect to('/hashfiles/list')
end