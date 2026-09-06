# frozen_string_literal: true

require "bundler"
require "rubygems/package"
require "tmpdir"

abort "Usage: bundle exec ruby dev/smoke_package.rb path/to/gem" unless ARGV.one?
package = Gem::Package.new(File.expand_path(ARGV.fetch(0)))
package.verify
bundler = Gem.bin_path("bundler", "bundle")
gem_home = Bundler.bundle_path.to_s

Dir.mktmpdir("solidus-nexi-runtime-") do |directory|
  gem_root = File.join(directory, "gem")
  package.extract_files(gem_root)
  specification = package.spec
  File.write(File.join(gem_root, "#{specification.name}.gemspec"), specification.to_ruby)
  gemfile = File.join(directory, "Gemfile")
  File.write(gemfile, <<~GEMFILE)
    source "https://rubygems.org"
    gem #{specification.name.dump}, #{specification.version.to_s.dump}, path: #{gem_root.dump}
  GEMFILE
  smoke = <<~RUNTIME
    require "solidus_nexi"
    abort "Loaded source checkout instead of package" unless SolidusNexi::Engine.root.realpath.to_s == File.realpath(ARGV.fetch(0))
    %w[solidus_dev_support puma].each do |name|
      abort "Development dependency leaked into runtime: \#{name}" if Gem.loaded_specs.key?(name)
    end
    puts "Packaged engine boots with runtime dependencies only"
  RUNTIME

  Bundler.with_unbundled_env do
    environment = {
      "BUNDLE_GEMFILE" => gemfile, "BUNDLE_PATH" => nil, "BUNDLE_PATH__SYSTEM" => "true",
      "GEM_HOME" => gem_home, "GEM_PATH" => ([gem_home] + Gem.path).uniq.join(File::PATH_SEPARATOR)
    }
    system(environment, Gem.ruby, bundler, "install", "--local", chdir: directory, exception: true)
    system(environment, Gem.ruby, bundler, "exec", Gem.ruby, "-e", smoke, gem_root,
      chdir: directory, exception: true)
  end
end
