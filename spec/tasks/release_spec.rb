# frozen_string_literal: true

require "open3"

RSpec.describe "release task", type: :model do
  it "cannot tag, push, or publish implicitly" do
    repository = File.expand_path("../..", __dir__)
    output, error, process = Open3.capture3(
      {"BUNDLE_GEMFILE" => File.join(repository, "Gemfile")},
      Gem.ruby,
      "-S",
      "bundle",
      "exec",
      "rake",
      "release",
      chdir: repository
    )

    expect(process).not_to be_success
    expect(output + error).to include("Automatic release is disabled")
  end
end
