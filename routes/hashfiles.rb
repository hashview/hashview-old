# encoding: utf-8
get '/hashfiles/list' do
  @hub_settings = HubSettings.first
  @customers = Customers.all(order: [:name.asc])
  @hashfiles = Hashfiles.all
  @cracked_status = {}
  @local_cracked_cnt = {}
  @local_uncracked_cnt = {}
#  @hub_download_cnt = {}
#  @hub_upload_cnt = {}

  @hashfiles.each do |hashfile|
    hashfile_cracked_count = repository(:default).adapter.select('SELECT COUNT(h.originalhash) FROM hashes h LEFT JOIN hashfilehashes a ON h.id = a.hash_id WHERE (a.hashfile_id = ? AND h.cracked = 1)', hashfile.id)[0].to_s
    hashfile_total_count = repository(:default).adapter.select('SELECT COUNT(h.originalhash) FROM hashes h LEFT JOIN hashfilehashes a ON h.id = a.hash_id WHERE a.hashfile_id = ?', hashfile.id)[0].to_s
    @local_cracked_cnt[hashfile.id] = hashfile_cracked_count.to_s
    @local_uncracked_cnt[hashfile.id] = hashfile_total_count.to_i - hashfile_cracked_count.to_i
    @cracked_status[hashfile.id] = hashfile_cracked_count.to_s + '/' + hashfile_total_count.to_s
    # hub upload cnt
#    if @hub_settings.status == 'registered'
#      @hashfile_hashes = Hashfilehashes.all(hashfile_id: hashfile.id)
#      upload_cnt = 0
#      download_cnt = 0
#      @hash_array = []
#      @hashfile_hashes.each do |entry|
#        # p 'HASH ID: ' + entry.hash_id.to_s
#        # Build list of locally cracked hashes per hashfile
#        local_cracked = Hashes.all(id: entry.hash_id, cracked: '1')
#        unless local_cracked.nil?
#          local_cracked.each do |hash|
#            element = {}
#            element['ciphertext'] = hash.originalhash
#            element['hashtype'] = hash.hashtype.to_s
#            # p 'ELEMENT: ' + element.to_s
#            @hash_array.push(element)
#          end
#        end
#      end
#      # p 'HASH_ARRAY: ' + @hash_array.to_s
#      # Submit query and record how many the hub doesnt have
#      hub_response = Hub.hashSearch(@hash_array)
#      hub_response = JSON.parse(hub_response)
#      if hub_response['status'] == '200'
#        @hub_hash_results = hub_response['hashes']
#        @hub_hash_results.each do |entry|
#          if entry['cracked'] == '0'
#            upload_cnt += 1
#          end
#        end
#      end

#      @hash_array = []
#      @hashfile_hashes.each do |entry|
#      # Build list of locally uncracked per hashfile
#        local_uncracked = Hashes.all(id: entry.hash_id, cracked: '0')
#        unless local_uncracked.nil? || local_uncracked.empty?
#          local_uncracked.each do |hash|
#            element = {}
#            element['ciphertext'] = hash.originalhash
#            element['hashtype'] = hash.hashtype.to_s
#            @hash_array.push(element)
#          end
#        end
#      end

#      # Submit query and record how many the hub doesn't have
#      hub_response = Hub.hashSearch(@hash_array)
#      hub_response = JSON.parse(hub_response)
#      if hub_response['status'] == '200'
#        @hub_hash_results = hub_response['hashes']
#        @hub_hash_results.each do |entry|
#          if entry['cracked'] == '1'
#            # p 'ENTRY' + entry.to_s
#            download_cnt += 1
#          end
#        end
#      end
#    else
#      upload_cnt = 0
#      download_cnt = 0
#    end

    # hub download cnt
#    @hub_download_cnt[hashfile.id] = download_cnt
#    @hub_upload_cnt[hashfile.id] = upload_cnt
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

