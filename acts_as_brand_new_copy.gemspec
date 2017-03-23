# coding: utf-8
lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'acts_as_brand_new_copy/version'

Gem::Specification.new do |spec|
  spec.name          = "acts_as_brand_new_copy"
  spec.version       = ActsAsBrandNewCopy::VERSION
  spec.authors       = ["Ben Cao"]
  spec.email         = ["ben@bencao.it"]
  spec.description   = "A ruby gem for active record which simplify the copy of very complex tree data."
  spec.summary       = "Just give me the object tree specification and callbacks, I will do all the rest for you."
  spec.homepage      = "https://github.com/bencao/acts_as_brand_new_copy"
  spec.license       = "MIT"

  spec.files         = `git ls-files`.split($/)
  spec.executables   = spec.files.grep(%r{^bin/}) { |f| File.basename(f) }
  spec.test_files    = spec.files.grep(%r{^(test|spec|features)/})
  spec.require_paths = ["lib"]

  spec.add_dependency "activesupport", "~> 3.2.13"
  spec.add_dependency "activerecord", "~> 3.2.13"
end
