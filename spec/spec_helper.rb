require 'coveralls'
Coveralls.wear!

require 'active_support'
require 'active_record'
require 'sqlite3'
require 'pry'
require 'database_cleaner'
require 'factory_girl'

db_config = YAML::load(IO.read('db/database.yml'))
db_file = db_config['development']['database']
File.delete(db_file) if File.exists?(db_file)
ActiveRecord::Base.configurations = db_config
ActiveRecord::Base.establish_connection('development')

RSpec.configure do |config|
  # == Mock Framework
  # If you prefer to use mocha, flexmock or RR, uncomment the appropriate line:
  config.mock_with :mocha

  config.before(:suite) do
    DatabaseCleaner.strategy = :transaction
    DatabaseCleaner.clean_with(:truncation)
  end

  config.before(:each) do
    DatabaseCleaner.start
  end

  config.after(:each) do
    DatabaseCleaner.clean
  end

  config.include FactoryGirl::Syntax::Methods
end
