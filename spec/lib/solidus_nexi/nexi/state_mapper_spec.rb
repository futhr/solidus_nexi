# frozen_string_literal: true

RSpec.describe SolidusNexi::Nexi::StateMapper do
  subject(:mapper) { described_class.new }

  it "maps a full reservation to pending" do
    result = mapper.map(summary: {"reservedAmount" => 10_000}, expected_amount_minor: 10_000)
    expect(result).to have_attributes(target_state: "pending", reconciliation_required: false)
  end

  it "maps a full charge to completed" do
    result = mapper.map(summary: {"chargedAmount" => 10_000}, expected_amount_minor: 10_000)
    expect(result.target_state).to eq("completed")
  end

  it "does not pretend a partial charge is supported" do
    result = mapper.map(summary: {"chargedAmount" => 5_000}, expected_amount_minor: 10_000)
    expect(result).to have_attributes(target_state: nil, reconciliation_required: true,
      reason: "unexpected_partial_charge")
  end

  it "prevents late events from regressing terminal Solidus state" do
    expect(mapper.transition_allowed?("completed", "pending")).to be(false)
    expect(mapper.transition_allowed?("void", "completed")).to be(false)
  end
end
