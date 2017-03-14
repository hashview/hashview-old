# encoding: utf-8
get '/agents/list' do
  @agents = Agents.all
  haml :agent_list
end

get '/agents/create' do
  haml :agent_edit
end

get '/agents/:id/edit' do
  @agent = Agents.first(:id => params[:id])
  haml :agent_edit
end

post '/agents/:id/edit' do
  agent = Agents.first(:id => params[:id])
  agent.name = params["name"]
  agent.save
  redirect to('/agents/list')
end

get '/agents/:id/delete' do
  agent = Agents.first(:id => params[:id])
  agent.destroy
  redirect to('/agents/list')
end

get '/agents/:id/authorize' do
  agent = Agents.first(:id => params[:id])
  agent.status = "Authorized"
  agent.save
  redirect to('/agents/list')
end

get '/agents/:id/deauthorize' do
  agent = Agents.first(:id => params[:id])
  agent.status = "Pending"
  agent.save
  redirect to('/agents/list')
end