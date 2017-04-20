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
          :port => '8443',
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
      response = RestClient::Request.execute(
          :method => :get,
          :url => url,
          :verify_ssl => false
      )
      p 'response: ' + response.body.to_s
      return response.body
    rescue RestClient::Exception => e
      return '{"error_msg" : "api call failed"}'
    end
  end

  def self.post(url, payload)
    begin
      p 'post: ' + payload.to_s
      response = RestClient::Request.execute(
          :method => :post,
          :url => url,
          :payload => payload.to_json,
          :headers => {:accept => :json},
          :verify_ssl => false #TODO VALIDATE!
      )
      p 'response: ' + response.body.to_s
      return response.body
    rescue RestClient::Exception => e
      puts e
      return '{"error_msg": "api call failed"}'
    end
  end

  ######### specific api functions #############

  def self.register()
    hub_settings = HubSettings.first
    url = "https://#{@server}/v1/register"
    payload = {}
    payload['uuid'] = hub_settings.uuid
    return self.post(url, payload)
  end

  def self.hashSearch(hash)
    hub_settings = HubSettings.first
    url = "https://#{@server}/v1/hashes/search"
    payload = {}
    payload['uuid'] = hub_settings.uuid
    payload['auth_key'] = hub_settings.auth_key
    payload['hash'] = hash
    return self.post(url, payload)
  end

  def self.hashReveal(hash, hashtype)
    hub_settings = HubSettings.first
    url = "https://#{@server}/v1/hashes/reveal"
    payload = {}
    payload['uuid'] = hub_settings.uuid
    payload['auth_key'] = hub_settings.auth_key
    payload['hash'] = hash
    payload['hashtype'] = hashtype
    return self.post(url, payload)
  end

  def self.statusAuth()
    hub_settings = HubSettings.first
    url = "https://#{@server}/v1/status/auth"
    payload = {}
    payload['uuid'] = hub_settings.uuid
    payload['auth_key'] = hub_settings.auth_key
    return self.post(url, payload)
  end

  def self.statusBalance()
    hub_settings = HubSettings.first
    url = "https://#{@server}/v1/status/balance"
    payload = {}
    payload['uuid'] = hub_settings.uuid
    payload['auth_key'] = hub_settings.auth_key
    return self.post(url, payload)
  end
end

### ROUTES #############################################

get '/hub/register' do

  hub_settings = HubSettings.first

  # TODO
  # Allow for a person to submit an (optional) email address for UUID / auth_key resets
  response = Hub.register
  response = JSON.parse(response)

  if response['status'] == '200'
    hub_settings.auth_key = response['auth_key']
    hub_settings.status = 'registered'
    hub_settings.save
  else
    flash[:error] = 'Error with registration.'
  end

  redirect to('/settings')
end


# TODO
# Should probably be :hash_id instead of :hash for privacy sake
get '/hub/reveal/:hashtype/:hash' do

  @hub_response = Hub.hashReveal(params[:hash], params[:hashtype])
  @hub_response = JSON.parse(@hub_response)

  if @hub_response['status'] == '200'

    # Add to local db
    entry = Hashes.first(hashtype: params[:hashtype], originalhash: params[:hash])
    if entry.nil?
      new_entry = Hashes.new
      new_entry.lastupdated =
      new_entry.originalhash = params[:hash]
      new_entry.hashtype = params[:hashtype]
      new_entry.cracked = '1'
      new_entry.plaintext = @hub_response['plaintext']
      new_entry.save
    else
      entry.plaintext = @hub_response['plaintext']
      entry.cracked = '1'
      entry.save
    end

    referer = request.referer.split('/')
    # We redirect the user back to where he came
    if referer[3] == 'search'
      # We came from Search we send back to search
      flash[:success] = 'Successfully unlocked password hash'
      redirect to('/search')
    elsif referer[3] == 'someuploadarea'
      # We came from uploads we send back to uploads
      # TODO
      redirect to('/jobs/list')
    end

  # if come from hashes search redirect back there
  # if come from hash importer redirect back there
  elsif @hub_response['status'] == 'error'
    p 'You dun goofed up'
  end
end

### Functions ##########################################

