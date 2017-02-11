$LOAD_PATH.unshift File.expand_path("../lib", __FILE__)


begin
  require 'rspec/core/rake_task'
  RSpec::Core::RakeTask.new(:spec)
rescue LoadError
end

begin
  require 'rspec/core/rake_task'

  RSpec::Core::RakeTask.new(:spec)

  task :default => :spec
rescue LoadError
  # no rspec available
end

task :build do
  system "gem build porterhouse.gemspec"
end
