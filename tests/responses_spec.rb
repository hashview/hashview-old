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

  def login_testuser
    @user = build(:user, username: "test", password: "omgplains", admin: true)
    @userid = User.create_test_user
    post '/login', {:username => @user.username, :password => @user.password}
    return @userid
  end

  # there has to be a better way to hook the end of a rake test
  def delete_testuser(id)
    puts "deleting test user #{id}"
    User.delete_test_user(id)
  end

  def test_login_response
    get '/login'
    assert_equal 200, last_response.status
  end

  def test_register_response
    get '/register'
    assert_equal 200, last_response.status
  end

  def test_successful_login
    userid = login_testuser
    assert last_response.include?('Set-Cookie')
    assert_equal "http://example.org/home", last_response.location
    follow_redirect!
    assert last_response.ok?
    assert last_response.body.include?("Cracked")
    delete_testuser(userid)
  end

  # this is a dummy/example test
  def test_authd_404_response
    userid = login_testuser
    get '/thisshouldneverexist'
    assert_equal last_response.status, 404
    delete_testuser(userid)
  end

  def test_home_response
    userid = login_testuser
    get '/home'
    assert last_response.ok?
    delete_testuser(userid)
  end

  # customer routes

  def test_customers_list_response
    userid = login_testuser
    get '/customers/list'
    assert_equal 200, last_response.status
    #assert last_response.body.include?("Add a New Customer")
    delete_testuser(userid)
  end

  def test_customers_create_response
    userid = login_testuser
    get '/customers/create'
    assert_equal 200, last_response.status
    #assert last_response.body.include?("Add a New Customer")
    delete_testuser(userid)
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
    # remember, if there are no customers in db, we redirct to create customer
    assert_equal 302, last_response.status
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

  def test_analytics_graph1_response
    userid = login_testuser
    get '/analytics/graph1'
    assert_equal 200, last_response.status
    delete_testuser(userid)
  end

  def test_analytics_graph2_response
    userid = login_testuser
    get '/analytics/graph2'
    assert_equal 200, last_response.status
    delete_testuser(userid)
  end

  def test_analytics_graph3_response
    userid = login_testuser
    get '/analytics/graph3'
    assert_equal 200, last_response.status
    delete_testuser(userid)
  end

  # download results

  def test_download_cracked_file_response
    userid = login_testuser
    get '/download'
    assert_equal 200, last_response.status
    delete_testuser(userid)
  end

  # dummy failed test

  def test_jobs_start_nonexistent_response
    userid = login_testuser
    get '/jobs/start/999999'
    assert_equal 200, last_response.status
    assert last_response.body.include?("No such job exists.")
    delete_testuser(userid)
  end

  # settings routes

  def test_settings_response
    userid = login_testuser
    get '/settings'
    assert_equal 200, last_response.status
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

  # purge routes

  def test_purge_response
    userid = login_testuser
    get '/purge'
    assert_equal 200, last_response.status
    delete_testuser(userid)
  end

end
