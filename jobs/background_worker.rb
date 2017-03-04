require 'rest-client'
require 'benchmark'

# one day, when I grow up...I'll be a ruby dev
# api calls
class Api
  @server = "localhost:4567"
  def self.get(url)
    begin
      response = RestClient::Request.execute(
          :method => :get,
          :url => url,
          :verify_ssl => false
      )
      return response.body
    rescue RestClient::Exception => e
      return '{"error_msg": "api call failed"}'
    end
  end

  def self.post(url, payload)
    begin
      response = RestClient::Request.execute(
          :method => :post,
          :url => url,
          :payload => payload.to_json,
          :headers => {:accept => :json},
          :verify_ssl => false
      )
      return response.body
    rescue RestClient::Exception => e
      puts e
      return '{"error_msg": "api call failed"}'
    end
  end

  # change status of jobtask
  def self.post_jobtask_status(jobtask_id, status)
    url = "https://#{@server}/v1/jobtask/#{jobtask_id}/status"
    payload = {}
    payload['status'] = status
    payload['job_id'] = jobtask_id
    return self.post(url, payload)
  end

  # change status of taskqueue item
  def self.post_queue_status(taskqueue_id, status)
    url = "https://#{@server}/v1/queue/#{taskqueue_id}/status"
    payload = {}
    payload['status'] = status
    payload['taskqueue_id'] = taskqueue_id
    return self.post(url, payload)
  end

  # get next item in queue
  def self.queue
    url = "https://#{@server}/v1/queue"
    return self.get(url)
  end

    # remove item from queue
  def self.queue_remove(queue_id)
    url = "https://#{@server}/v1/queue/#{queue_id}/remove"
    return self.get(url)
  end

  # jobtask details
  def self.jobtask(jobtask_id)
    url = "https://#{@server}/v1/jobtask/#{jobtask_id}"
    return self.get(url)
  end

  # job details
  def self.job(job_id)
    url = "https://#{@server}/v1/job/#{job_id}"
    return self.get(url)
  end

  # download hashfile
  def self.hashfile(jobtask_id, hashfile_id)
    url = "https://#{@server}/v1/jobtask/#{jobtask_id}/hashfile/#{hashfile_id}"
    return self.get(url)
  end

  # wordlists
  def self.wordlists()
    url = "https://#{@server}/v1/wordlist"
    return self.get(url)
  end

  # download a wordlist
  def self.wordlist()
    url = "https://#{@server}/v1/wordlist/:id"
    return self.get(url)
  end

  # save wordlist to disk
  def self.save_wordlist(localpath='control/wordlists/thisisjustatest.txt')
    File.write(localpath)
  end

  # upload crack file
  def self.upload_crackfile(jobtask_id, crack_file, run_time=0)
    url = "https://#{@server}/v1/jobtask/#{jobtask_id}/crackfile/upload"
    puts "attempting upload #{crack_file}"
    begin
      request = RestClient::Request.new(
            :method => :post,
            :url => url,
            :payload => {
              :multipart => true,
              :file => File.new(crack_file, 'rb'),
              :runtime => run_time
            },
            :verify_ssl => false
      )
      response = request.execute
    rescue RestClient::Exception => e
      puts e
      return '{error_msg: \'api call failed\'}'
    end
  end

  # # parses hashcat output
  # def hashcatParser(filepath)
  #   status = {}
  #   File.open(filepath).each_line do |line|
  #     if line.start_with?('Time.Started.')
  #       status['Time_Started'] = line.split(': ')[-1].strip
  #     elsif line.start_with?('Time.Estimated.')
  #       status['Time_Estimated'] = line.split(': ')[-1].strip
  #     elsif line.start_with?('Recovered.')
  #       status['Recovered'] = line.split(': ')[-1].strip
  #     elsif line.start_with?('Input.Mode.')
  #       status['Input_Mode'] = line.split(': ')[-1].strip
  #     elsif line.start_with?('Speed.Dev.')
  #       item = line.split(': ')
  #       gpu = item[0].gsub!('Speed.Dev.', 'Speed Dev ').gsub!('.', '')
  #       status[gpu] = line.split(': ')[-1].strip
  #     elsif line.start_with?('HWMon.Dev.')
  #       item = line.split('.: ')
  #       gpu = item[0].gsub!('HWMon.Dev.', 'HWMon Dev ').gsub!('.', '')
  #       status[gpu] = line.split('.: ')[-1].strip
  #     end
  #     return status
  #   end
  # end

  # # api call to upload hashcat output for dashboard
  # def self.upload_hcoutput(filepath)
  #   url = "https://#{@server}/v1/hcoutput/status"
  #   status = hashcatParser(filepath)
  #   return self.post(url, status)
  # end

end


class LocalAgent
  @queue = :hashcat

  def self.perform()

    # this is our background worker for the task queue
    # other workers will be ran from a hashview agent
    begin
      sleep 4
      puts "checking for tasks"
      jdata = Api.queue
      jdata = JSON.parse(jdata)

      # we must have an item from the queue before we start processing
      if jdata['type'] != 'Error'

        # take queue item and set status to running
        Api.post_queue_status(jdata['id'], 'Running')

        # set the jobtask to running
        Api.post_jobtask_status(jdata['jobtask_id'], 'Running')

        # we need job details for hashfile id
        job = Api.job(jdata['job_id'])
        job = JSON.parse(job)

        # we need to get task_id which is stored in jobtasks
        jobtask = Jobtasks.first(id: jdata['jobtask_id'])

        # we dont need to download the wordlist b/c we are local agent, we already have them
        # wordlists Api.wordlists()
        # puts wordlists
        #puts Api.wordlist()

        # generate hashfile via api
        Api.hashfile(jobtask['id'], job['hashfile_id'])

        # run hashcat, do real work!
        puts "running hashcat job"
        cmd = jdata['command']
        puts cmd
        run_time = Benchmark.realtime do
          system(cmd)
        end

        # set jobtask status to importing
        Api.post_jobtask_status(jdata['jobtask_id'], 'Importing')

        # upload results
        crack_file = 'control/outfiles/hc_cracked_' + jdata['job_id'].to_s + '_' + jobtask['task_id'].to_s + '.txt'
        Api.upload_crackfile(jobtask.id, crack_file, run_time)

        # change status to completed for jobtask
        Api.post_jobtask_status(jdata['jobtask_id'], 'Completed')

        # set taskqueue item to complete and remove from queue
        Api.post_queue_status(jdata['id'], 'Completed')
        Api.queue_remove(jdata['id'])
      end
    rescue StandardError => e
      $stderr << e.message
      $stderr << e.backtrace.join('\n')
    end
  end
end


