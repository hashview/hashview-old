require 'rest-client'
require 'benchmark'

@hashcatbinpath = JSON.parse(File.read('config/agent_config.json'))['hc_binary_path']

# one day, when I grow up...I'll be a ruby dev
# api calls

class Api

  # obtain remote ip and port from local config
  begin
    options = JSON.parse(File.read('config/agent_config.json'))
    @server = options['ip'] + ":" + options['port']
    @uuid = options['uuid']
    @hashcatbinpath = options['hc_binary_path'].to_s
  rescue
    "Error reading config/agent_config.json. Did you run rake db:provision_agent ???"
  end

  ######### generic api handling of GET and POST request ###########
  def self.get(url)
    begin
      response = RestClient::Request.execute(
          :method => :get,
          :url => url,
          :cookies => {:agent_uuid => @uuid},
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
          :cookies => {:agent_uuid => @uuid},
          :verify_ssl => false
      )
      return response.body
    rescue RestClient::Exception => e
      puts e
      return '{"error_msg": "api call failed"}'
    end
  end

  ######### specific api funcions #############

  # get heartbeat when we are looking for work to do
  def self.heartbeat()
    url = "https://#{@server}/v1/agents/#{@uuid}/heartbeat"
    puts "HEARTBEETING"
    return self.get(url)
  end

  # post hearbeat is used when agent is working
  def self.post_heartbeat(payload)
    url = "https://#{@server}/v1/agents/#{@uuid}/heartbeat"
    puts "HEARTBEETING"
    return self.post(url, payload)
  end

  # change status of jobtask
  def self.post_jobtask_status(jobtask_id, status)
    url = "https://#{@server}/v1/jobtask/#{jobtask_id}/status"
    payload = {}
    payload['status'] = status
    payload['jobtask_id'] = jobtask_id
    return self.post(url, payload)
  end

  # change status of taskqueue item
  def self.post_queue_status(taskqueue_id, status)
    url = "https://#{@server}/v1/queue/#{taskqueue_id}/status"
    payload = {}
    payload['status'] = status
    payload['taskqueue_id'] = taskqueue_id
    payload['agent_uuid'] = @uuid
    return self.post(url, payload)
  end

  # get next item in queue
  def self.queue
    url = "https://#{@server}/v1/queue"
    return self.get(url)
  end

  # get specific item from queue (must already be assigned to agent)
  def self.queue_by_id(id)
    url = "https://#{@server}/v1/queue/#{id}"
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
            :cookies => {:agent_uuid => @uuid},
            :verify_ssl => false
      )
      response = request.execute
    rescue RestClient::Exception => e
      puts e
      return '{error_msg: \'api call failed\'}'
    end
  end

  def self.stats(hc_devices, hc_perfstats)
    url = "https://#{@server}/v1/agents/#{@uuid}/stats"
    payload = {}
    payload['cpu_count'] = hc_devices['cpus']
    payload['gpu_count'] = hc_devices['gpus']
    payload['benchmark'] = hc_perfstats
    puts payload
    return self.post(url, payload)
  end
end

# parses hashcat output
def hashcatParser(filepath)
  status = {}
  File.open(filepath).each_line do |line|
    if line.start_with?('Time.Started.')
      status['Time_Started'] = line.split(': ')[-1].strip
    elsif line.start_with?('Time.Estimated.')
      status['Time_Estimated'] = line.split(': ')[-1].strip
    elsif line.start_with?('Recovered.')
      status['Recovered'] = line.split(': ')[-1].strip
    elsif line.start_with?('Input.Mode.')
      status['Input_Mode'] = line.split(': ')[-1].strip
    elsif line.start_with?('Speed.Dev.')
      item = line.split(': ')
      gpu = item[0].gsub!('Speed.Dev.', 'Speed Dev ').gsub!('.', '')
      status[gpu] = line.split(': ')[-1].strip
    elsif line.start_with?('HWMon.Dev.')
      item = line.split('.: ')
      gpu = item[0].gsub!('HWMon.Dev.', 'HWMon Dev ').gsub!('.', '')
      status[gpu] = line.split('.: ')[-1].strip
    end
  end
  return status
end

def hashcatDeviceParser(output)
  gpus = 0
  cpus = 0
  output.each_line do |line|
    if line.include?('Type')
      if line.split(': ')[-1].strip.include?('CPU')
        cpus += 1
      elsif line.split(': ')[-1].strip.include?('GPU')
        gpus += 1
      end
    end
  end
  puts "agent has #{cpus} CPUs"
  puts "agent has #{gpus} GPUs"
  return cpus, gpus
end

def hashcatBenchmarkParser(output)
  max_speed = ""
  output.each_line do |line|
    if line.start_with?('Speed.Dev.#')
      max_speed = line.split(': ')[-1].to_s
    end
  end
  puts "agent max cracking speed (single NTLM hash):\n #{max_speed}"
  return max_speed
end

def getHashcatPid
  pid = `ps -ef | grep hashcat | grep hc_cracked_ | grep -v 'ps -ef' | grep -v 'sh \-c' | awk '{print $2}'`
  return pid.chomp
end

# replace the placeholder binary path with the user defined path to hashcat binary
def replaceHashcatBinPath(cmd)
  hashcatbinpath = JSON.parse(File.read('config/agent_config.json'))['hc_binary_path']
  cmd = cmd.gsub('@HASHCATBINPATH@', hashcatbinpath)
  return cmd
end

# this function provides the master server with basic information about the agent
def hc_benchmark()
  cmd = @hashcatbinpath + ' -b -m 1000'
  hc_perfstats = `#{cmd}`
  return  hc_perfstats
end

def hc_device_list()
  cmd = @hashcatbinpath + ' -I'
  hc_devices = `#{cmd}`
  return  hc_devices
end

# is hashcat working? if so, how fast are you? provide basic information to master server
hc_cpus, hc_gpus = hashcatDeviceParser(hc_device_list)
hc_devices = {}
hc_devices['gpus'] = hc_gpus
hc_devices['cpus'] = hc_cpus
hc_perfstats = hashcatBenchmarkParser(hc_benchmark)
Api.stats(hc_devices, hc_perfstats)


class LocalAgent
  @queue = :hashcat

  def self.perform()

    # this is our background worker for the task queue
    # other workers will be ran from a hashview agent

    while(1)
      sleep(4)

      # find pid
      pid = getHashcatPid

      # wait a bit to avoid race condition
      if !pid.nil? and File.exist?('control/tmp/agent_current_task.txt')
        sleep(10)
        pid = getHashcatPid
      end

      # ok either do nothing or start working
      if pid.nil?
        puts "AGENT IS WORKING RIGHT NOW"
      else

        # if we have taskqueue tmp file locally, delete it
        File.delete('control/tmp/agent_current_task.txt') if File.exist?('control/tmp/agent_current_task.txt')

        # send heartbeat without hashcat status
        payload = {}
        payload['agent_status'] = 'Idle'
        payload['hc_benchmark'] = 'example data'
        heartbeat = Api.post_heartbeat(payload)
        puts '======================================'
        heartbeat = JSON.parse(heartbeat)
        puts heartbeat

        if heartbeat['type'] == 'Message' and heartbeat['msg'] == 'START'

          jdata = Api.queue_by_id(heartbeat['task_id'])
          jdata = JSON.parse(jdata)

          # we must have an item from the queue before we start processing
          if jdata['type'] != 'Error'

            # save task data to tmp to signify we are working
            File.open('control/tmp/agent_current_task.txt', 'w') do |f|
              f.write(jdata)
            end

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

            # get our hashcat command and sub out the binary path
            cmd = jdata['command']
            cmd = replaceHashcatBinPath(cmd)
            puts cmd

            # this variable is used to determine if the job was canceled
            @canceled = false

            # # thread off hashcat
            thread1 = Thread.new {
              @run_time = Benchmark.realtime do
                system(cmd)
              end
            }

            @jobid = jdata['job_id']
            # # continue to hearbeat while running job. look for a stop command
            catch :mainloop do
              while thread1.status do
                sleep 4
                puts "WORKING IN THREAD"
                puts "WORKING ON ID: #{jdata['id']}"
                payload = {}
                payload['agent_status'] = 'Working'
                payload['agent_task'] = jdata['id']
                # provide hashcat status with hearbeat
                payload['hc_status'] = hashcatParser("control/outfiles/hcoutput_#{@jobid}.txt")
                heartbeat = Api.post_heartbeat(payload)
                heartbeat = JSON.parse(heartbeat)

                if heartbeat['msg'] == 'Canceled'
                  @canceled = true
                  Thread.kill(thread1)
                  # for some reason hashcat doesnt always get killed when terminating the thread.
                  # manually kill it to be certain
                  pid = getHashcatPid
                  if pid
                    `kill -9 #{pid}`
                  end
                  throw :mainloop
                end
              end
            end

            # set jobtask status to importing
            Api.post_jobtask_status(jdata['jobtask_id'], 'Importing')

            # upload results
            crack_file = 'control/outfiles/hc_cracked_' + jdata['job_id'].to_s + '_' + jobtask['task_id'].to_s + '.txt'
            Api.upload_crackfile(jobtask.id, crack_file, @run_time)

            # remove task data tmp file
            File.delete('control/tmp/agent_current_task.txt') if File.exist?('control/tmp/agent_current_task.txt')

            # change status to completed for jobtask
            if @canceled
              Api.post_jobtask_status(jdata['jobtask_id'], 'Canceled')
            else
              Api.post_jobtask_status(jdata['jobtask_id'], 'Completed')
            end

            # set taskqueue item to complete and remove from queue
            Api.post_queue_status(jdata['id'], 'Completed')
          end
        end
      end
    end
  end
end