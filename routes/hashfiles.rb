# encoding: utf-8
get '/hashfiles/list' do
  @hub_settings = HubSettings.first
  @customers = Customers.order(Sequel.asc(:name)).all
  @hashfiles = Hashfiles.all
  @cracked_status = {}
  @local_cracked_cnt = {}
  @local_uncracked_cnt = {}

  @hashfiles.each do |hashfile|
    hashfile_cracked_count = HVDB.fetch('SELECT COUNT(h.originalhash) as count FROM hashes h LEFT JOIN hashfilehashes a ON h.id = a.hash_id WHERE (a.hashfile_id = ? AND h.cracked = 1)', hashfile.id)[:count]
    hashfile_cracked_count = hashfile_cracked_count[:count]
    hashfile_total_count = HVDB.fetch('SELECT COUNT(h.originalhash) as count FROM hashes h LEFT JOIN hashfilehashes a ON h.id = a.hash_id WHERE a.hashfile_id = ?', hashfile.id)[:count]
    hashfile_total_count = hashfile_total_count[:count]
    @local_cracked_cnt[hashfile.id] = hashfile_cracked_count.to_s
    @local_uncracked_cnt[hashfile.id] = hashfile_total_count.to_i - hashfile_cracked_count.to_i
    @cracked_status[hashfile.id] = hashfile_cracked_count.to_s + '/' + hashfile_total_count.to_s
  end

  haml :hashfile_list
end

get '/hashfiles/delete' do
  varWash(params)

  hashfilehashes = HVDB[:hashfilehashes]
  hashfilehashes.filter(hashfile_id: params[:hashfile_id]).delete

  hashfile = HVDB[:hashfiles]
  hashfile.filter(id: params[:hashfile_id]).delete

  flash[:success] = 'Successfully removed hashfile.'

  redirect to('/hashfiles/list')
end