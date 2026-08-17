# frozen_string_literal: true

require "fileutils"
require "tmpdir"
require "generators/solidus_nexi/install/install_generator"

RSpec.describe SolidusNexi::Generators::InstallGenerator, type: :generator do
  let(:destination_root) { Dir.mktmpdir("solidus-nexi-generator-") }
  let(:options) { {} }
  let(:generator) { described_class.new([], options, destination_root:) }

  before do
    allow(generator).to receive(:route)
    allow(generator).to receive(:run)
    allow(generator).to receive(:say)
  end

  after do
    FileUtils.remove_entry(destination_root) if File.exist?(destination_root)
  end

  it "installs the initializer, route, and migrations without changing the database when declined" do
    allow(generator).to receive(:ask).and_return("n")

    generator.invoke_all

    initializer = File.read(File.join(destination_root, "config/initializers/solidus_nexi.rb"))
    expect(initializer).to include("SolidusNexi.configure", "NEXI_CHECKOUT_API_KEY")
    expect(generator).to have_received(:route).with("mount SolidusNexi::Engine, at: '/solidus_nexi'")
    expect(generator).to have_received(:run)
      .with("bin/rails railties:install:migrations FROM=solidus_nexi").once
    expect(generator).to have_received(:say).with("Run bin/rails db:migrate before enabling Nexi Checkout.")
  end

  context "with automatic migrations enabled" do
    let(:options) { {auto_run_migrations: true} }

    it "copies and runs the engine migrations without prompting" do
      allow(generator).to receive(:ask)

      generator.invoke_all

      expect(generator).not_to have_received(:ask)
      expect(generator).to have_received(:run).with("bin/rails db:migrate").once
    end
  end

  it "makes generator failures visible to the host application" do
    expect(described_class.exit_on_failure?).to be(true)
  end
end
