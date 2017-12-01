# encoding: utf-8

get '/wordlists/list' do
  @wordlists = Wordlists.all

  haml :wordlist_list
end

get '/wordlists/add' do
  haml :wordlist_add
end

get '/wordlists/delete/:id' do
  varWash(params)

  @wordlist = Wordlists.first(id: params[:id])
  if !@wordlist
    flash[:error] = 'No such wordlist exists. '
    redirect to('/wordlists/list')
  else
    # check if wordlist is in use
    @task_list = Tasks.select(wl_id: @wordlist.id).all
    unless @task_list.empty?
      flash[:error] = 'This word list is associated with a task, it cannot be deleted.'
      redirect to('/wordlists/list')
    end

    # Remove from filesystem
    begin
      File.delete(@wordlist.path)
    rescue
      flash[:warning] = 'No file found on disk.'
    end

    # delete from db
    @wordlist.destroy

  end
  redirect to('/wordlists/list')
end

post '/wordlists/upload/' do
  varWash(params)
  if !params[:file] || params[:file].nil?
    flash[:error] = 'You must specify a file.'
    redirect to('/wordlists/add')
  end
  if !params[:name] || params[:name].empty?
    flash[:error] = 'You must specify a name for your wordlist.'
    redirect to('/wordlists/add')
  end

  # Replace white space with underscore.  We need more filtering here too
  upload_name = params[:name]
  upload_name = upload_name.downcase.tr(' ', '_')

  # Change to date/time ?
  rand_str = rand(36**36).to_s(36)

  # Save to file
  file_name = "control/wordlists/wordlist-#{upload_name}-#{rand_str}.txt"

  wordlist = Wordlists.new
  wordlist.type = 'static'
  wordlist.name = upload_name
  wordlist.path = file_name
  wordlist.size = 0
  wordlist.checksum = nil
  wordlist.lastupdated = Time.now
  wordlist.save

  File.open(file_name, 'wb') { |f| f.write(params[:file][:tempfile].read) }
  Resque.enqueue(WordlistImporter)
  Resque.enqueue(WordlistChecksum)

  redirect to('/wordlists/list')
end
