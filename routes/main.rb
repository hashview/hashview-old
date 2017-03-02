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
  if isOldVersion
    return "You need to perform some upgrade steps. Check instructions <a href=\"https://github.com/hashview/hashview/wiki/Upgrading-Hashview\">here</a>"
  end
  @results = `ps awwux | grep -i Hashcat | egrep -v "(grep|screen|SCREEN|resque|^$)"`
  @jobs = Jobs.all(:order => [:id.asc])
  @jobtasks = Jobtasks.all
  @tasks = Tasks.all

  @recentlycracked = repository(:default).adapter.select('SELECT CONCAT(timestampdiff(minute, h.lastupdated, NOW()) ) AS time_period, h.plaintext, a.username FROM hashes h LEFT JOIN hashfilehashes a ON h.id = a.hash_id WHERE (h.cracked = 1) ORDER BY h.lastupdated DESC LIMIT 10')

  @customers = Customers.all
  @active_jobs = Jobs.all(fields: [:id, :status], status: 'Running') | Jobs.all(fields: [:id, :status], status: 'Importing') | Jobs.all(fields: [:id, :status], status: 'Queued')

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
      Hashfilehashes.all(fields: [:hash_id], hashfile_id: j.hashfile_id).each do |entry|
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

