require 'test_helper'
require 'application_checker'

tmp_dir = "#{File.dirname(__FILE__)}/fixtures/tmp"

if defined? BASE_ROOT
  BASE_ROOT.replace tmp_dir
else
  BASE_ROOT = tmp_dir
end
FileUtils.mkdir_p BASE_ROOT

# Stub out methods on upgrader class
module Rails
  module Upgrading
    class ApplicationChecker
      attr_reader :alerts
      
      def base_path
        BASE_ROOT + "/"
      end
      
      def in_rails_app?
        true
      end
      
      def initialize
        @alerts = {}
      end
      
      def alert(title, text, more_info_url, culprits)
        @alerts[title] = [text, more_info_url, culprits]
      end
    end
  end
end

class ApplicationCheckerTest < ActiveSupport::TestCase
  def setup
    @checker = Rails::Upgrading::ApplicationChecker.new
    @old_dir = Dir.pwd
    
    Dir.chdir(BASE_ROOT)
  end
  
  def test_check_ar_methods_in_controller
    make_file("app/controllers", "post_controller.rb", "Post.find(:all)")
    @checker.check_ar_methods

    assert @checker.alerts.has_key?("Soon-to-be-deprecated ActiveRecord calls")
  end
  
  def test_check_ar_methods_in_models
    make_file("app/models", "post.rb", "Post.find(:all)")
    @checker.check_ar_methods

    assert @checker.alerts.has_key?("Soon-to-be-deprecated ActiveRecord calls")
  end
  
  def test_named_scope_left_over
    make_file("app/models", "post.rb", "named_scope :failure")
    @checker.check_ar_methods

    assert @checker.alerts.has_key?("named_scope is now just scope")
  end
  
  def test_check_routes
    make_file("config/", "routes.rb", "  map.connect 'fail'")
    @checker.check_routes

    assert @checker.alerts.has_key?("Old router API")
  end
  
  def test_check_for_old_test_help
    make_file("test/", "test_helper.rb", "  require 'test_help'")
    @checker.check_test_help

    assert @checker.alerts.has_key?("Deprecated test_help path")
  end
  
  def test_check_for_old_test_help_with_double_quotes
    make_file("test/", "test_helper.rb", "  require \"test_help\"")
    @checker.check_test_help

    assert @checker.alerts.has_key?("Deprecated test_help path")
  end
  
  def test_check_for_old_test_help_doesnt_see_test_helper
    make_file("test/", "test_helper.rb", "  require 'test_helper'")
    @checker.check_test_help

    assert !@checker.alerts.has_key?("Deprecated test_help path")
  end
  
  def test_check_lack_of_app_dot_rb
    @checker.check_environment

    assert @checker.alerts.has_key?("New file needed: config/application.rb")
  end
  
  def test_check_environment_syntax
    make_file("config/", "environment.rb", "config.frameworks = []")
    @checker.check_environment
    
    assert @checker.alerts.has_key?("Old environment.rb")    
  end
  
  def test_check_gems
    make_file("config/", "environment.rb", "config.gem 'rails'")
    @checker.check_gems
    
    assert @checker.alerts.has_key?("Old gem bundling (config.gems)")
  end
  
  def test_check_mailer_syntax
    make_file("app/models/", "notifications.rb", "def signup\nrecipients @users\n end")
    @checker.check_mailers

    assert @checker.alerts.has_key?("Old ActionMailer class API")
  end
  
  def test_check_mailer_api
    make_file("app/controllers/", "thing_controller.rb", "def signup\n Notifications.deliver_signup\n end")
    @checker.check_mailers
    
    assert @checker.alerts.has_key?("Deprecated ActionMailer API")
  end
  
  def test_check_generators
    make_file("vendor/plugins/thing/generators/thing/", "thing_generator.rb", "def manifest\n m.whatever\n end")
    @checker.check_generators
    
    assert @checker.alerts.has_key?("Old Rails generator API")    
  end
  
  def test_check_plugins
    make_file("vendor/plugins/rspec-rails/", "whatever.rb", "def rspec; end")
    @checker.check_plugins
    
    assert @checker.alerts.has_key?("Known broken plugins")
  end
  
  def test_ignoring_comments
    make_file("config/", "routes.rb", "#  map.connect 'fail'")
    @checker.check_routes

    assert !@checker.alerts.has_key?("Old router API")
  end
  
  def test_check_deprecated_constants_in_app_code
    make_file("app/controllers/", "thing_controller.rb", "class ThingController; THING = Rails.env; end;")
    @checker.check_deprecated_constants
    
    assert @checker.alerts.has_key?("Deprecated constant(s)")
  end
  
  def test_check_deprecated_constants_in_lib
    make_file("lib/", "extra_thing.rb", "class ExtraThing; THING = Rails.env; end;")
    @checker.check_deprecated_constants
    
    assert @checker.alerts.has_key?("Deprecated constant(s)")
  end
  
  def teardown
    clear_files
    
    Dir.chdir(@old_dir)
  end
  
  def make_file(where, name=nil, contents=nil)
    FileUtils.mkdir_p "#{BASE_ROOT}/#{where}"
    File.open("#{BASE_ROOT}/#{where}/#{name}", "w+") do |f|
      f.write(contents)
    end if name
  end
  
  def clear_files
    FileUtils.rm_rf(Dir.glob("#{BASE_ROOT}/*"))
  end
end