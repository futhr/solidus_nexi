# frozen_string_literal: true

require "fileutils"
require "open3"
require "tmpdir"
require "rubygems/package"

RSpec.describe "gem package", type: :model do
  it "excludes stray files and verifies packaged metadata and source bytes" do
    repository = File.expand_path("../..", __dir__)
    specification = Gem::Specification.load(File.join(repository, "solidus_nexi.gemspec"))

    Dir.mktmpdir("solidus-nexi-package-spec-") do |directory|
      (specification.files + %w[solidus_nexi.gemspec dev/verify_package.rb]).each do |path|
        destination = File.join(directory, path)
        FileUtils.mkdir_p(File.dirname(destination))
        FileUtils.cp(File.join(repository, path), destination)
      end
      File.write(File.join(directory, "lib/.env"), "must not ship")
      File.write(File.join(directory, "lib/private.pem"), "must not ship")
      File.symlink(File.join(repository, "Gemfile"), File.join(directory, "lib/linked.rb"))
      artifact = "solidus_nexi-#{SolidusNexi::VERSION}.gem"
      _, error, build = Open3.capture3(
        Gem.ruby, "-rrubygems/package", "-e", "Gem::Package.build(Gem::Specification.load(ARGV.fetch(0)))",
        "solidus_nexi.gemspec", chdir: directory
      )
      expect(build).to be_success, error

      output, error, verification = Open3.capture3(Gem.ruby, "dev/verify_package.rb", artifact, chdir: directory)
      expect(verification).to be_success, output + error
      expect(output).to include("SHA256")
      contents = Gem::Package.new(File.join(directory, artifact)).contents
      expect(contents).not_to include("lib/.env", "lib/private.pem", "lib/linked.rb")

      gemspec_path = File.join(directory, "solidus_nexi.gemspec")
      original_gemspec = File.read(gemspec_path)
      File.write(gemspec_path, original_gemspec.sub("spec.summary =", "spec.summary = \"Changed summary\" #"))
      _, error, verification = Open3.capture3(Gem.ruby, "dev/verify_package.rb", artifact, chdir: directory)
      expect(verification).not_to be_success
      expect(error).to include("Packaged summary does not match")
      File.write(gemspec_path, original_gemspec)

      File.write(File.join(directory, "README.md"), "changed after packaging")
      _, error, verification = Open3.capture3(Gem.ruby, "dev/verify_package.rb", artifact, chdir: directory)
      expect(verification).not_to be_success
      expect(error).to include("Packaged file differs from source: README.md")
    end
  end
end
