# oh my, does this mean we are legit if we are testing things?!
# this is straight out of sinatra recipes
require File.expand_path '../../helpers/test_helper.rb', __FILE__

if ENV['RACK_ENV'] != 'test'
  puts "tests can only run under the RACK_ENV=test environment"
  exit
end

class MyTest < MiniTest::Test

  include Rack::Test::Methods
  include FactoryGirl::Syntax::Methods

  FactoryGirl.define do
    factory :user, class: User do
      username "test"
      password "omgplains"
      admin true
    end
  end

  def app
    Sinatra::Application
  end

  ##############################
  #### Supporting Functions ####
  ##############################

  # Deletes single user by id
  def delete_testuser(id)
    puts "deleting test user #{id}"
    User.delete_test_user(id)
  end

  # Deletes all users
  def delete_all_users()
    puts 'Deleteing all users'
    User.delete_all_users
  end

  # Logs in a single test user
  def login_testuser
    @user = build(:user, username: "test", password: "omgplains", admin: true)
    @userid = User.create_test_user
    post '/login', {:username => @user.username, :password => @user.password}
    return @userid
  end

  #######################
  #### Route Testing ####
  #######################

  #### Register Tests ####

  def test_register_get
    # Should allow access to /register if no users exist.
    delete_all_users
    puts '[+] Testing /register GET [1 of 2]'
    get '/register'
    assert last_response.ok?
    assert last_response.body.include?('Create a New Admin Account')

    # Should redirect user to /login if at least 1 user exists.
    puts '[+] Testing /register GET [2 of 2]'
    User.create_test_user
    get '/register'
    assert last_response.redirection? 
    assert_equal 'http://example.org/', last_response.location
    follow_redirect! # Redirect to /
    assert last_response.redirection?
    assert_equal "http://example.org/login", last_response.location
    follow_redirect! # redirect to /login
    assert last_response.ok?
    assert last_response.body.include?('Login')
    delete_all_users    
  end

  def test_register_post
    puts '[+] Testing /register POST'
    delete_all_users
    post '/register', {username: 'reg_test', password: 'tryharder', confirm: 'tryharder'}
    assert last_response.redirection?
    assert_equal "http://example.org/login", last_response.location
    follow_redirect!
    assert last_response.ok?
    assert last_response.body.include?('Login')
    delete_all_users
  end

  #### Login Tests ####

  def test_login_get
    puts '[+] Testing /login GET [1 of 2]'
    delete_all_users
    get '/login'
    # if no users exist in db this will redirect
    p 'last response: ' + last_response.to_s
    assert last_response.redirection?
    assert_equal "http://example.org/register", last_response.location
    follow_redirect!
    assert last_response.ok?
    assert last_response.body.include?('Create a New Admin Account')

    puts '[+] Testing /login GET [2 of 2]'
    User.create_test_user
    get '/login'
    assert last_response.ok?
    delete_all_users
  end

  def test_login_post
    puts '[+] Testing /login POST'
    userid = login_testuser
    assert last_response.include?('Set-Cookie')
    assert last_response.redirection?
    assert_equal 'http://example.org/home', last_response.location
    follow_redirect!
    assert last_response.ok?
    assert last_response.body.include?('Hashview')
    delete_testuser(userid)
  end

  #### Home Tests ####

  def test_home_get
    puts '[+] Testing /home GET'
    userid = login_testuser
    get '/home'
    assert last_response.ok?
    delete_testuser(userid)
  end

  #### Customer Tests ####

  def test_customers_list_get
    puts '[+] Testing /customers/list GET'
    userid = login_testuser
    get '/customers/list'
    assert last_response.ok?
    assert last_response.body.include?('Add a New Customer')
    delete_testuser(userid)
  end

  def test_customers_create_get
    puts '[+] Testing /customers/create GET'
    userid = login_testuser
    get '/customers/create'
    assert last_response.ok?
    delete_testuser(userid)
  end

  def test_customers_create_post
    puts '[+] Testing /customers/create POST'
    login_testuser
    post '/customers/create', {name: 'cust_test', desc: 'cust_test_desc'}
    assert last_response.redirection?
    assert_equal 'http://example.org/customers/list', last_response.location
    follow_redirect!
    assert last_response.ok?
    assert last_response.body.include?('Add a New Customer')
  end
 
  # job routes

  def test_jobs_list_response
    userid = login_testuser
    get '/jobs/list'
    assert_equal 200, last_response.status
    #assert last_response.body.include?("Create a New Job")
    delete_testuser(userid)
  end

  def test_jobs_create_response
    userid = login_testuser
    get '/jobs/create'
    assert_equal 200, last_response.status
    #assert last_response.body.include?("Create a New Job")
    delete_testuser(userid)
  end

  # task routes

  def test_tasks_list_response
    userid = login_testuser
    get '/tasks/list'
    assert_equal 200, last_response.status
    #assert last_response.body.include?("Create Task")
    delete_testuser(userid)
  end

  def test_tasks_create_response
    userid = login_testuser
    get '/tasks/create'
    assert_equal 200, last_response.status
    #assert last_response.body.include?("Create Task")
    delete_testuser(userid)
  end

  # analytics routes

  def test_analytics_response
    userid = login_testuser
    get '/analytics'
    assert_equal 200, last_response.status
    delete_testuser(userid)
  end

  # Total Hashes Cracked
  def test_analytics_Total_Hashes_Cracked_response
    userid = login_testuser
    get '/analytics/graph/TotalHashesCracked'
    assert_equal 200, last_response.status
    delete_testuser(userid)
  end

  # Complexity Breakdown
  def test_analytics_Complexity_Breakdown_response
    userid = login_testuser
    get '/analytics/graph/ComplexityBreakdown'
    assert_equal 200, last_response.status
    delete_testuser(userid)
  end

  # Charset Breakdown
  def test_analytics_Charset_Breakdown_response
    userid = login_testuser
    get '/analytics/graph/CharsetBreakdown'
    assert_equal 200, last_response.status
    delete_testuser(userid)
  end

  # Password Counts by Length
  def test_analytics_Password_Count_By_Length_response
    userid = login_testuser
    get '/analytics/PasswordsCountByLength'
    assert_equal 200, last_response.status
    delete_testuser(userid)
  end

  # Top Ten Basewords
  def test_analytics_Top_Ten_Basewords_response
    userid = login_testuser
    get '/analytics/Top10BaseWords'
    assert_equal 200, last_response.status
    delete_testuser(userid)
  end

  # Accounts with Weak Passwords
  def test_analytics_Weak_Passwords_response
    userid = login_testuser
    get 'analytics/AccountsWithWeakPasswords'
    assert_equal 200, last_response.status
    delete_testuser(userid)
  end

  # download results


  # Need to update with fake crack data in order to test download

  #def test_download_cracked_file_response
  #  userid = login_testuser
  #  get '/download'
  #  assert_equal 200, last_response.status
  #  delete_testuser(userid)
  #end

  # dummy failed test

 
  # Needs to be updated seince we now 302 all success & failures
  #def test_jobs_start_nonexistent_response
  #  userid = login_testuser
  #  get '/jobs/start/999999'
  #  #assert_equal 302, last_response.status
  #  assert last_response.body.include?("No such job exists.")
  #  delete_testuser(userid)
  #end

  # settings routes

  def test_settings_response
    userid = login_testuser
    get '/settings'
    assert_equal 200, last_response.status
    delete_testuser(userid)
  end

  # email tests

  def test_invalid_email_send_response
    # remove email attr from user
    userid = login_testuser
    user = User.first(:id => userid)
    user.email = ''
    user.save
    get '/test/email'
    assert last_response.redirection?
    assert_equal "http://example.org/settings", last_response.location
    follow_redirect!
    assert last_response.ok?
    #assert last_response.body.include?('Current logged on user has no email address associated')
    delete_testuser(userid)
  end

  def test_valid_email_send_response
    userid = login_testuser
    get '/test/email'
    assert last_response.redirection?
    assert_equal "http://example.org/settings", last_response.location
    follow_redirect!
    assert last_response.ok?
    #assert last_response.body.include?('Email sent')
    delete_testuser(userid)
  end

  # wordlists routes

  def test_wordlists_list_response
    userid = login_testuser
    get '/wordlists/list'
    assert_equal 200, last_response.status
    delete_testuser(userid)
  end

  def test_wordlists_add_response
    userid = login_testuser
    get '/wordlists/add'
    assert_equal 200, last_response.status
    delete_testuser(userid)
  end

  # search routes

  def test_search_response
    userid = login_testuser
    get '/search'
    assert_equal 200, last_response.status
    delete_testuser(userid)
  end

  # agent routes
  # get '/agents/list' do
  # get '/agents/create' do
  # get '/agents/:id/edit' do
  # post '/agents/:id/edit' do
  # get '/agents/:id/delete' do
  # get '/agents/:id/authorize' do
  # get '/agents/:id/deauthorize' do

  def test_agents_list_response
    userid = login_testuser
    get '/agents/list' 
    assert_equal 200, last_response.status
    delete_testuser(userid)
  end

  def test_agents_create_response
    userid = login_testuser
    get '/agents/create'
    assert_equal 200, last_response.status
    delete_testuser(userid)
  end

  # api routes
  # get '/v1/notauthorized' do
  # get '/v1/queue' do
  # get '/v1/queue/:id' do
  # get '/v1/queue/:id/remove' do
  # post '/v1/queue/:taskqueue_id/status' do
  # post '/v1/jobtask/:jobtask_id/status' do
  # get '/v1/jobtask/:id' do
  # get '/v1/job/:id' do
  # get '/v1/wordlist' do
  # get '/v1/wordlist/:id' do
  # get '/v1/jobtask/:jobtask_id/hashfile/:hashfile_id' do
  # post '/v1/jobtask/:jobtask_id/crackfile/upload' do
  # post '/v1/hcoutput/status' do
  # post '/v1/agents/:uuid/heartbeat' do
  # get '/v1/agents/:uuid/authorize' do
  # post '/v1/agents/:uuid/stats' do

  # TODO implement api tests

end
