# oh my, does this mean we are legit if we are testing things?!
# this is straight out of sinatrat recipes
require File.expand_path '../../helpers/test_helper.rb', __FILE__

class MyTest < MiniTest::Test

  include Rack::Test::Methods
  include FactoryGirl::Syntax::Methods

  FactoryGirl.define do
    factory :user, class: User do
      username "test"
      password "test"
      admin true
    end
  end

  def app
    Sinatra::Application
  end

  def login_testuser
    @user = build(:user, username: "test", password: "test", admin: true)
    post '/login', {:username => @user.username, :password => @user.password}
  end

  def test_login_response
    get '/login'
    assert_equal last_response.status, 200
  end

  def test_register_response
    get '/register'
    assert_equal last_response.status, 200
  end

  def test_successful_login
    login_testuser
    assert last_response.include?('Set-Cookie')
    assert_equal "http://example.org/home", last_response.location
    follow_redirect!
    assert last_response.ok?
    assert last_response.body.include?("Cracked")
  end

  # this is a dummy/example test
  def test_authd_404_response
    login_testuser
    get '/thisshouldneverexist'
    assert_equal last_response.status, 404
  end

  def test_home_response
    login_testuser
    get '/home'
    assert last_response.ok?
  end

  def test_customers_list_response
    login_testuser
    get '/customers/list'
    assert_equal last_response.status, 200
    #assert last_response.body.include?("Add a New Customer")
  end

  def test_jobs_list_response
    login_testuser
    get '/jobs/list'
    assert_equal last_response.status, 200
    #assert last_response.body.include?("Create a New Job")
  end

  def test_tasks_list_response
    login_testuser
    get '/tasks/list'
    assert_equal last_response.status, 200
    #assert last_response.body.include?("Create Task")
  end

  def test_analytics_response
    login_testuser
    get '/analytics'
    assert_equal last_response.status, 200
  end

  def test_download_cracked_file_response
    login_testuser
    get '/download'
    assert_equal last_response.status, 200
  end

  def test_jobs_start_nonexistent_response
    login_testuser
    get '/jobs/start/999999'
    assert_equal last_response.status, 200
    assert last_response.body.include?("No such job exists.")
  end

end
