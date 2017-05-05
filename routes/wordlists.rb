# encoding: utf-8
require_relative '../jobs/init' # this shouldnt be needed?
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
    return 'no such wordlist exists'
  else
    # check if wordlist is in use
    @task_list = Tasks.all(wl_id: @wordlist.id)
    if !@task_list.empty?
      flash[:error] = 'This word list is associated with a task, it cannot be deleted.'
      redirect to('/wordlists/list')
    end
  
    # remove from filesystem
    File.delete(@wordlist.path)
  
    # delete from db
    @wordlist.destroy

    # Update our magic wordlist
    # Resque.enqueue(MagicWordlist)
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
  wordlist.name = upload_name 
  wordlist.path = file_name
  wordlist.size = 0
  wordlist.lastupdated = Time.now()
  wordlist.save

  File.open(file_name, 'wb') { |f| f.write(params[:file][:tempfile].read) }

  # Update our magic wordlist
  # Resque.enqueue(MagicWordlist)
  redirect to('/wordlists/list')
end
