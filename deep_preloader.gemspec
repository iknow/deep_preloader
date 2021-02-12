# coding: utf-8
lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'deep_preloader/version'

Gem::Specification.new do |spec|
  spec.name          = "deep_preloader"
  spec.version       = DeepPreloader::VERSION
  spec.authors       = ["iKnow Team"]
  spec.email         = ["dev@iknow.jp"]

  spec.summary       = %q{Explicit preloader for ActiveRecord}
  spec.homepage      = "http://github.com/iknow/deep_preloader"
  spec.license       = "MIT"

  spec.files         = `git ls-files -z`.split("\x0").reject { |f| f.match(%r{^(test|spec|features)/}) }
  spec.bindir        = "exe"
  spec.executables   = spec.files.grep(%r{^exe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  spec.add_dependency "activerecord", '>= 6.1.2'

  spec.add_development_dependency "bundler"
  spec.add_development_dependency "rake", "~> 10.0"
  spec.add_development_dependency "rspec"
  spec.add_development_dependency "database_cleaner"
  spec.add_development_dependency "minitest"

  spec.add_development_dependency "byebug"
  spec.add_development_dependency "pry"
  spec.add_development_dependency "method_source"
  spec.add_development_dependency "appraisal"
  spec.add_development_dependency "sqlite3"
end
