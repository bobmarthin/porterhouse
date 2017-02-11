lib = File.expand_path('../lib/', __FILE__)
$:.unshift lib unless $:.include?(lib)

require "porterhouse/version"

Gem::Specification.new do |s|
  s.name        = "porterhouse"
  s.version     = Porterhouse::VERSION
  s.platform    = Gem::Platform::RUBY
  s.authors     = ["bobmarthin"]
  s.email       = [""]
  s.homepage    = "https://github.com/bobmarthin/porterhouse"
  s.summary     = "Framework to orchestrate management of docker based stacks"
  s.description = "Framework to orchestrate management of docker based stacks"
  s.license     = 'MIT'
  s.has_rdoc    = false

  s.add_dependency('colorize')

  s.add_development_dependency('rake')

  s.files         = Dir.glob("{bin,lib}/**/*") + %w(porterhouse.gemspec LICENSE)
  s.executables   = Dir.glob('bin/**/*').map { |file| File.basename(file) }
  s.test_files    = nil
  s.require_paths = ['lib']
end
