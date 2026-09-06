# frozen_string_literal: true

require "rubygems/package"
require "digest"
require "tmpdir"

abort "Usage: ruby dev/verify_package.rb path/to/solidus_nexi-VERSION.gem" unless ARGV.one?

artifact = File.expand_path(ARGV.fetch(0))
abort "Gem artifact does not exist: #{artifact}" unless File.file?(artifact)

package = Gem::Package.new(artifact)
package.verify
packaged_spec = package.spec
source_spec = Gem::Specification.load(File.expand_path("../solidus_nexi.gemspec", __dir__))
abort "Could not load solidus_nexi.gemspec" unless source_spec

expected_artifact = "#{source_spec.name}-#{source_spec.version}.gem"
abort "Expected #{expected_artifact}, got #{File.basename(artifact)}" unless File.basename(artifact) == expected_artifact
abort "Packaged gemspec does not match the source gemspec" unless packaged_spec.files.sort == source_spec.files.sort
abort "Archive contents do not match the packaged gemspec" unless package.contents.sort == packaged_spec.files.sort

%i[name version authors email summary description homepage licenses metadata required_ruby_version dependencies].each do |attribute|
  unless packaged_spec.public_send(attribute) == source_spec.public_send(attribute)
    abort "Packaged #{attribute} does not match the source gemspec"
  end
end

Dir.mktmpdir("solidus-nexi-package-") do |directory|
  package.extract_files(directory)
  packaged_spec.files.each do |path|
    source = File.expand_path("../#{path}", __dir__)
    extracted = File.join(directory, path)
    unless File.file?(extracted) && !File.symlink?(extracted) &&
        Digest::SHA256.file(extracted) == Digest::SHA256.file(source)
      abort "Packaged file differs from source: #{path}"
    end
  end
end

required = %w[
  CHANGELOG.md
  CONTRIBUTING.md
  LICENSE.md
  README.md
  SECURITY.md
  config/routes.rb
  lib/solidus_nexi.rb
  lib/solidus_nexi/engine.rb
  lib/solidus_nexi/version.rb
  lib/generators/solidus_nexi/install/install_generator.rb
  lib/generators/solidus_nexi/install/templates/initializer.rb
]
missing = required - packaged_spec.files
missing << "db/migrate" unless packaged_spec.files.grep(%r{\Adb/migrate/.*\.rb\z}).any?
missing << "app/views" unless packaged_spec.files.grep(%r{\Aapp/views/}).any?
abort "Missing packaged files: #{missing.join(", ")}" unless missing.empty?

forbidden = packaged_spec.files.select do |path|
  path.match?(%r{\A(?:\.env|\.git|coverage/|dev/|pkg/|sandbox/|spec/|tmp/)}) ||
    path.include?("spree_dibs") || path.include?("gateway/dibs")
end
abort "Forbidden files in package: #{forbidden.join(", ")}" unless forbidden.empty?

metadata = packaged_spec.metadata
abort "RubyGems MFA is not required" unless metadata["rubygems_mfa_required"] == "true"
abort "Push host is not restricted to RubyGems.org" unless metadata["allowed_push_host"] == "https://rubygems.org"
abort "Source URI is not tied to this version" unless metadata["source_code_uri"].end_with?("/v#{packaged_spec.version}")

puts "Verified #{File.basename(artifact)} (#{packaged_spec.files.length} files)"

puts "SHA256 #{Digest::SHA256.file(artifact).hexdigest}"
