# encoding: utf-8
get '/' do
  @users = User.all
  
  if @users.empty?
    redirect to('/register')
  elsif !validSession?
    redirect to('/login')
  else
    redirect to('/home')
  end
end

get '/home' do

  @results = `ps awwux | grep -i Hashcat | egrep -v "(grep|screen|SCREEN|resque|^$)"`
  @jobs = Jobs.order(Sequel.asc(:queued_at)).all

  @jobtasks = Jobtasks.all
  @tasks = Tasks.all
  @taskqueues = Taskqueues.all
  @agents = Agents.all

  # not used anymore
  # @recentlycracked = repository(:default).adapter.select('SELECT CONCAT(timestampdiff(minute, h.lastupdated, NOW()) ) AS time_period, h.plaintext, a.username FROM hashes h LEFT JOIN hashfilehashes a ON h.id = a.hash_id WHERE (h.cracked = 1) ORDER BY h.lastupdated DESC LIMIT 10')

  @customers = Customers.all
  @active_jobs = Jobs.where(:status => 'Running').select(:id, :status)

  # nvidia works without sudo:
  @gpustatus = `nvidia-settings -q \"GPUCoreTemp\" | grep Attribute | grep -v gpu | awk '{print $3,$4}'`
  if @gpustatus.empty?
    @gpustatus = `lspci | grep "VGA compatible controller" | cut -d: -f3 | sed 's/\(rev a1\)//g'`
  end
  @gpustatus = @gpustatus.split("\n")
  @gpustat = []
  @gpustatus.each do |line|
    unless line.chomp.empty?
      line = line.delete('.')
      @gpustat << line
    end
  end

  @jobs.each do |j|
    if j.status == 'Running'
      # gather info for statistics

      @hash_ids = Array.new
      Hashfilehashes.where(hashfile_id: j.hashfile_id).select(:hash_id).each do |entry|
        @hash_ids.push(entry.hash_id)
      end

      @alltargets = Hashes.count(id: @hash_ids)
      @crackedtargets = Hashes.count(id: @hash_ids, cracked: 1)

      @progress = (@crackedtargets.to_f / @alltargets.to_f) * 100
      # parse a hashcat status file
      @hashcat_status = hashcatParser('control/outfiles/hcoutput_' + j.id.to_s + '.txt')
    end
  end

  haml :home
end

