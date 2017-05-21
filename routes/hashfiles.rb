# encoding: utf-8
get '/hashfiles/list' do
  @hub_settings = HubSettings.first
  @customers = Customers.all(order: [:name.asc])
  @hashfiles = Hashfiles.all
  @cracked_status = {}
  @local_cracked_cnt = {}
  @local_uncracked_cnt = {}
  @hub_download_cnt = {}
  @hub_upload_cnt = {}

  @hashfiles.each do |hashfile|
    hashfile_cracked_count = repository(:default).adapter.select('SELECT COUNT(h.originalhash) FROM hashes h LEFT JOIN hashfilehashes a ON h.id = a.hash_id WHERE (a.hashfile_id = ? AND h.cracked = 1)', hashfile.id)[0].to_s
    hashfile_total_count = repository(:default).adapter.select('SELECT COUNT(h.originalhash) FROM hashes h LEFT JOIN hashfilehashes a ON h.id = a.hash_id WHERE a.hashfile_id = ?', hashfile.id)[0].to_s
    @local_cracked_cnt[hashfile.id] = hashfile_cracked_count.to_s
    @local_uncracked_cnt[hashfile.id] = hashfile_total_count.to_i - hashfile_cracked_count.to_i
    @cracked_status[hashfile.id] = hashfile_cracked_count.to_s + '/' + hashfile_total_count.to_s
    # hub upload cnt
    if @hub_settings.status == 'registered'
      @hashfile_hashes = Hashfilehashes.all(hashfile_id: hashfile.id)
      upload_cnt = 0
      download_cnt = 0
      @hashfile_hashes.each do |entry|
        local_cracked = Hashes.first(id: entry.hash_id, cracked: '1')
        unless local_cracked.nil?
          hub_response = Hub.hashSearch(local_cracked.originalhash)
          hub_response = JSON.parse(hub_response)
          if hub_response['status'] == '200' && hub_response['cracked'] == '0'
            upload_cnt += 1
          end
        end
        local_uncracked = Hashes.first(id: entry.hash_id, cracked: '0')
        unless local_uncracked.nil?
          hub_response = Hub.hashSearch(local_uncracked.originalhash)
          hub_response = JSON.parse(hub_response)
          if hub_response['status'] == '200' && hub_response['cracked'] == '1'
            download_cnt += 1
          end
        end
      end
    else
      upload_cnt = 0
      download_cnt = 0
    end
    # hub download cnt
    @hub_download_cnt[hashfile.id] = download_cnt
    @hub_upload_cnt[hashfile.id] = upload_cnt
  end

  haml :hashfile_list
end

get '/hashfiles/delete' do
  varWash(params)

  @hashfilehashes = Hashfilehashes.all(hashfile_id: params[:hashfile_id])
  @hashfilehashes.destroy unless @hashfilehashes.empty?

  @hashfile = Hashfiles.first(id: params[:hashfile_id])
  @hashfile.destroy unless @hashfile.nil?

  flash[:success] = 'Successfuly removed hashfile.'

  redirect to('/hashfiles/list')
end

