# frozen_string_literal: true

RSpec.describe SolidusNexi::Nexi::RetryAfter do
  let(:now) { Time.utc(2026, 8, 17, 12, 0, 0) }

  it "parses delta seconds and HTTP dates" do
    seconds = SolidusNexi::Nexi::RateLimitError.new("limited", retry_after: "45")
    date = SolidusNexi::Nexi::RateLimitError.new(
      "limited",
      retry_after: "Mon, 17 Aug 2026 12:02:00 GMT"
    )

    expect(described_class.delay(seconds, now:)).to eq(45)
    expect(described_class.delay(date, now:)).to eq(120)
  end

  it "uses bounded safe delays for missing, past, malformed, and excessive values" do
    expect(described_class.delay(StandardError.new, now:)).to eq(30)
    expect(described_class.delay(
      SolidusNexi::Nexi::RateLimitError.new("limited", retry_after: "invalid"),
      now:
    )).to eq(30)
    expect(described_class.delay(
      SolidusNexi::Nexi::RateLimitError.new("limited", retry_after: "0"),
      now:
    )).to eq(1)
    expect(described_class.delay(
      SolidusNexi::Nexi::RateLimitError.new("limited", retry_after: "99999"),
      now:
    )).to eq(3_600)
  end
end
