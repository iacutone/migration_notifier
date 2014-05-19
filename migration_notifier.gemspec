# coding: utf-8
lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'migration_notifier/version'

Gem::Specification.new do |spec|
  spec.name          = "migration_notifier"
  spec.version       = MigrationNotifier::VERSION
  spec.authors       = ["Eric Iacutone"]
  spec.email         = ["eric.iacutone@gmail.com"]
  spec.summary       = %q{Notification in terminal of new migrations.}
  spec.description   = %q{Everyone forgets to run rake db:migrate.}
  spec.homepage      = ""
  spec.license       = "MIT"

  spec.files         = `git ls-files -z`.split("\x0")
  spec.executables   = spec.files.grep(%r{^bin/}) { |f| File.basename(f) }
  spec.test_files    = spec.files.grep(%r{^(test|spec|features)/})
  spec.require_paths = ["lib"]

  spec.add_development_dependency "bundler", "~> 1.0"
  spec.add_development_dependency "rake"
  spec.add_development_dependency "rspec"
  spec.add_development_dependency "pry"
  # spec.add_dependency 'rb-fsevent', '>= 0.9.3'
  # spec.add_dependency 'rb-inotify', '>= 0.9'
end
