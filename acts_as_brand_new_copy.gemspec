# coding: utf-8
lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'acts_as_brand_new_copy/version'

Gem::Specification.new do |spec|
  spec.name          = "acts_as_brand_new_copy"
  spec.version       = ActsAsBrandNewCopy::VERSION
  spec.authors       = ["Ben Cao"]
  spec.email         = ["benb88@gmail.com"]
  spec.description   = "A ruby gem for active record which simplify the copy of very complex tree data."
  spec.summary       = "Just give me the object tree specification and callbacks, I will do all the rest for you."
  spec.homepage      = "https://github.com/bencao/acts_as_brand_new_copy"
  spec.license       = "MIT"

  spec.files         = `git ls-files`.split($/)
  spec.executables   = spec.files.grep(%r{^bin/}) { |f| File.basename(f) }
  spec.test_files    = spec.files.grep(%r{^(test|spec|features)/})
  spec.require_paths = ["lib"]

  spec.add_development_dependency "bundler", "~> 1.3"
  spec.add_development_dependency "rake", "~> 10.0.4"
  spec.add_development_dependency "rspec", "~> 2.13.0"
  spec.add_development_dependency "mocha", "~> 0.13.3"
  spec.add_development_dependency "sqlite3", "~> 1.3.7"
  spec.add_development_dependency "database_cleaner"
  spec.add_development_dependency "factory_girl"
  spec.add_development_dependency "factory_girl_rails"
  spec.add_development_dependency "pry"
  spec.add_development_dependency "pry-theme"
  spec.add_development_dependency "pry-nav"
  spec.add_development_dependency "codeclimate-test-reporter"
  spec.add_dependency "activesupport", "~> 3.2.13"
  spec.add_dependency "activerecord", "~> 3.2.13"
end
