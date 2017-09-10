require 'rest-client'
require 'benchmark'

# one day, when I grow up...I'll be a ruby dev
# hub calls
class Hub

  # obtain remote ip and port from local config
  begin
    # Provision new config if none exists.
    unless File.exist?('config/hub_config.json')
      hub_config = {
          :host => 'hub.hashview.io',
          :port => '443',
      }
      File.open('config/hub_config.json', 'w') do |f|
        f.write(JSON.pretty_generate(hub_config))
      end
    end

    options = JSON.parse(File.read('config/hub_config.json'))
    @server = options['host'] + ':' + options['port']

    @hub_settings = HubSettings.first
    @auth_key = @hub_settings.auth_key
    if @hub_settings.uuid.nil?
      p 'Generating new UUID'
      uuid = SecureRandom.hex(10)
      # Add hyphens, (i am ashamed at how dumb this is)
      uuid.insert(15, '-')
      uuid.insert(10, '-')
      uuid.insert(5, '-')
      @hub_settings.uuid = uuid
      @hub_settings.save
    end

  rescue
    'Error reading config/hub_config.json. Did you run rake db:provision_agent ???'
  end

  ######### generic api handling of GET and POST request ###########
  def self.get(url)
    begin
      p 'get: ' + url.to_s

      hub_settings = HubSettings.first
      response = RestClient::Request.execute(
        :method => :get,
        :url => url,
        :cookies => {:uuid => hub_settings.uuid, :auth_key => hub_settings.auth_key},
        :timeout => nil,
        :open_timeout => nil,
        #:verify_ssl => false
        :verify_ssl => true
      )
      p 'response: ' + response.body.to_s
      return response.body
    rescue Errno::ECONNREFUSED
      return '{"error_msg": "api call failed"}'
    rescue RestClient::Exception => e
      return '{"error_msg" : "api call failed"}'
    end
  end

  def self.post(url, payload)
    begin
      p 'post: ' + payload.to_s
      hub_settings = HubSettings.first
      p 'cookie: ' + hub_settings.uuid.to_s + ' ' + hub_settings.auth_key.to_s
      response = RestClient::Request.execute(
        :method => :post,
        :url => url,
        :payload => payload.to_json,
        :headers => {:accept => :json},
        :cookies => {:uuid => hub_settings.uuid, :auth_key => hub_settings.auth_key},
        :timeout => nil,
        :open_timeout => nil,
        #:verify_ssl => false #TODO VALIDATE
        :verify_ssl => true
      )
      p 'response: ' + response.body.to_s
      return response.body
    rescue Errno::ECONNREFUSED
      return '{"error_msg": "api call failed"}'
    rescue RestClient::Exception => e
      return '{"error_msg": "api call failed"}'
    end
  end

  ######### specific api functions #############

  def self.register(action)
    hub_settings = HubSettings.first
    url = "https://#{@server}/v1/register"
    payload = {}
    payload['action'] = action
    payload['uuid'] = hub_settings.uuid
    payload['email'] = hub_settings.email unless hub_settings.email.nil? || hub_settings.email.empty?
    self.post(url, payload)
  end

  def self.hashSearch(hash_array)
    url = "https://#{@server}/v1/hashes/search"
    payload = {}
    payload['hashes'] = hash_array
    self.post(url, payload)
  end

  def self.getSupportedHashtypes()
    url = "https://#{@server}/v1/hashes/supported_hashtypes"
    self.get(url)
  end

  def self.hashReveal(hash_array)
    url = "https://#{@server}/v1/hashes/reveal"
    payload = {}
    payload['hashes'] = hash_array
    self.post(url, payload)
  end

  def self.hashUpload(hash_array)
    url = "https://#{@server}/v1/hashes/upload"
    payload = {}
    payload['hashes'] = hash_array
    self.post(url, payload)
  end

  def self.statusAuth()
    url = "https://#{@server}/v1/status/auth"
    payload = {}
    self.post(url, payload)
  end

end

### ROUTES #############################################

get '/hub' do
  varWash(params)
  @hub_settings = HubSettings.first
  @customers = Customers.order(Sequel.asc(:name)).all
  @hashfiles = Hashfiles.all

  @cracked_by_hashtype_count = {}
  hub_response = Hub.getSupportedHashtypes
  hub_response = JSON.parse(hub_response)
  if hub_response['status'] == '200'
    @hub_supported_hashtypes = hub_response['hashtypes']
    @hub_supported_hashtypes.each do |hashtype|
      hashtype_cracked_count = HVDB.fetch('SELECT COUNT(originalhash) FROM hashes WHERE (hashtype = ? AND cracked = 1)', hashtype)[0].to_s
      hashtype_total_count = HVDB.fetch('SELECT COUNT(originalhash) FROM hashes WHERE hashtype = ?', hashtype)[0].to_s
      @cracked_by_hashtype_count[hashtype] = hashtype_cracked_count.to_s + '/' + hashtype_total_count.to_s unless hashtype_total_count.to_s == '0'
    end
  end

  haml :hub
end

get '/hub/register' do
  varWash(params)
  hub_settings = HubSettings.first

  response = Hub.register('new')
  response = JSON.parse(response)

  if response['status'] == '200'
    hub_settings.auth_key = response['auth_key']
    hub_settings.status = 'registered'
    hub_settings.email = param[:email] if params[:email]
    hub_settings.save
    flash[:success] = 'Hub registration success.'
  else
    flash[:error] = 'Hub registration failed.'
  end

  redirect to('/settings')
end

get '/hub/hash/reveal/hash/:hash_id' do
  varWash(params)

  hash = Hashes.first(id: params[:hash_id], cracked: '0')
  if hash.nil?
    flash[:error] = 'Failed to reveal: non-existant local hash.'
  else
    @hash_array = []
    element = {}
    element['ciphertext'] = hash.originalhash
    element['hashtype'] = hash.hashtype.to_s
    @hash_array.push(element)

    hub_response = Hub.hashReveal(@hash_array)
    hub_response = JSON.parse(hub_response)
    # p 'HUB ReSPONSE: ' + hub_response.to_s
    if hub_response['status'] == '200'
      @hashes = hub_response['hashes']
      @hashes.each do |element|
        # Add to local db
        # p 'CIPHER TEXT: ' + element['ciphertext'].to_s
        entry = Hashes.first(hashtype: element['hashtype'], originalhash: element['ciphertext'])
        if entry.nil?
          new_entry = Hashes.new
          new_entry.lastupdated = Time.now()
          new_entry.originalhash = element['ciphertext']
          new_entry.hashtype = element['hashtype']
          new_entry.cracked = '1'
          new_entry.plaintext = element['plaintext']
          new_entry.save
        else
          entry.plaintext = element['plaintext']
          entry.cracked = '1'
          entry.save
        end
      end
    end
  end

  referer = request.referer.split('/')
  # We redirect the user back to where he came
  if referer[3] == 'search'
    # We came from Search we send back to search
    flash[:success] = 'Successfully unlocked hash'
    redirect to('/search')
  elsif referer[3] == 'jobs'
    flash[:success] = 'Unlocked 1 Hash'
    redirect to("/jobs/#{referer[4]}")
  else
    p request.referer.to_s
    p referer[3].to_s
  end
end

get '/hub/hash/reveal/hashfile/:hashfile_id' do
  varWash(params)

  @hash_array = []

  @hashfile_hashes = Hashfilehashes.where(hashfile_id: params[:hashfile_id]).all
  @hashfile_hashes.each do |entry|
    hash = Hashes.first(id: entry.hash_id, cracked: '0')
    unless hash.nil?
      element = {}
      element['ciphertext'] = hash.originalhash
      element['hashtype'] = hash.hashtype.to_s
      @hash_array.push(element)
    end
  end

  hub_response = Hub.hashReveal(@hash_array)
  hub_response = JSON.parse(hub_response)
  hub_count = 0
  if hub_response['status'] == '200'
    @hashes = hub_response['hashes']
    @hashes.each do |element|
      # Add to local db
      entry = Hashes.first(hashtype: element['hashtype'], originalhash: element['ciphertext'])
      entry.lastupdated = Time.now()
      entry.plaintext = element['plaintext']
      entry.cracked = '1'
      entry.save
      hub_count = hub_count + 1
    end
  end

  flash[:success] = 'Hashview Hub unlocked ' + hub_count.to_s + ' hashes!'
  redirect to("/jobs/assign_tasks?job_id=#{params[:job_id]}")
end

get '/hub/hash/upload/hash/:id' do
  varWash(params)
  hash = Hashes.first(id: params[:id], cracked: 1)
  if hash.nil?
    flash[:error] = 'Error uploading hash'
  else
    @hash_array = []
    element = {}
    element['ciphertext'] = hash.originalhash
    element['hashtype'] = hash.hashtype.to_s
    element['plaintext'] = hash.plaintext
    @hash_array.push(element)
    hub_response = Hub.hashUpload(@hash_array)
    hub_response = JSON.parse(hub_response)
    flash[:error] = hub_response['message'] if hub_response['status'] != '200'

    referer = request.referer.split('/')
    if referer[3] == 'search'
      flash[:success] = 'Successfully uploaded hash!' if hub_response['status'] == '200'
    end
  end
  # TODO detect referer came from and redirect accordingly
  redirect to('/search')
end

get '/hub/hash/upload/hashfile/:hashfile_id' do
  varWash(params)
  @hash_array = []

  @hashfile_hashes = Hashfilehashes.where(hashfile_id: params[:hashfile_id]).all
  @hashfile_hashes.each do |entry|
    hash = Hashes.first(id: entry.hash_id, cracked: '1')
    unless hash.nil?
      element = {}
      element['ciphertext'] = hash.originalhash
      element['hashtype'] = hash.hashtype.to_s
      element['plaintext'] = hash.plaintext
      @hash_array.push(element)
    end
  end

  hub_response = Hub.hashUpload(@hash_array)
  hub_response = JSON.parse(hub_response)
  if hub_response['status'] == '200'
    flash[:success] = 'Successfully uploaded hashes.'
  end

  redirect to('/hashfiles/list')
end

get '/hub/hash/reveal/hashtype/:hashtype' do
  varWash(params)

  @hash_array = []
  @hashes = Hashes.where(hashtype: params[:hashtype], cracked: '0').all
  unless @hashes.nil?
    @hashes.each do |entry|
      element = {}
      element['ciphertext'] = entry.originalhash
      element['hashtype'] = params[:hashtype]
      @hash_array.push(element)

    end
  end

  cnt = 0
  hub_response = Hub.hashReveal(@hash_array)
  hub_response = JSON.parse(hub_response)
  if hub_response['status'] == '200'
    @hashes = hub_response['hashes']
    @hashes.each do |element|
      cnt = cnt + 1
      # Add to local db
      entry = Hashes.first(hashtype: element['hashtype'], originalhash: element['ciphertext'])
      entry.lastupdated = Time.now
      entry.plaintext = element['plaintext']
      entry.cracked = '1'
      entry.save
    end
    flash[:success] = 'Successfully unlocked: ' + cnt.to_s + ' hashes!'
  end

  redirect to('/hub')
end

### Functions ##########################################

