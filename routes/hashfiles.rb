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

  # First check to see if any jobs exists where hashfile is used
  @jobs = Jobs.select(hashfile_id: params[:hashfile_id]).all
  unless @jobs.empty?
    flash[:error] = 'Fail to delete Hashfile. Hashfile exists in a job.'
    redirect to('/hashfiles/list')
  end

  # Next we identify what the dynamic wordlist id is
  @hashfiles = Hashfiles.first(id: params[:hashfile_id])
  wordlist_id = @hashfiles[:wl_id]

  # Next we remove any tasks using a dynamic wordlist
  @tasks = HVDB[:tasks]
  @tasks.filter(wl_id: wordlist_id).delete

  # Next Remove Dynamic Wordlists
  @wordlists = HVDB[:wordlists]
  @wordlists.filter(id: wordlist_id).delete

  # Remove username to password associations
  hashfilehashes = HVDB[:hashfilehashes]
  hashfilehashes.filter(hashfile_id: params[:hashfile_id]).delete

  # Remove hashfile
  hashfile = HVDB[:hashfiles]
  hashfile.filter(id: params[:hashfile_id]).delete

  # Remove extraneous hashes
  HVDB.run('DELETE h FROM hashes h LEFT JOIN hashfilehashes a ON h.id = a.hash_id WHERE(a.hashfile_id is NULL AND h.cracked = 0)')

  flash[:success] = 'Successfully removed hashfile.'

  redirect to('/hashfiles/list')
end