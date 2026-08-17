# frozen_string_literal: true

RSpec.describe SolidusNexi::PublicUrl do
  it "accepts public HTTPS URLs and exact origins" do
    expect(described_class.valid_https?("https://checkout.merchant.se/terms")).to be(true)
    expect(described_class.valid_https?("https://checkout.merchant.se", origin: true)).to be(true)
    expect(described_class.valid_https?("https://[2606:4700:4700::1111]/terms")).to be(true)
  end

  it "rejects reserved names, non-public literals, credentials, and non-origins" do
    invalid_urls = %w[
      https://shop.example/terms
      https://merchant.example.com/terms
      https://localhost/terms
      https://127.0.0.1/terms
      https://10.0.0.1/terms
      https://169.254.1.2/terms
      https://192.0.2.10/terms
      https://[::1]/terms
      https://user:pass@checkout.merchant.se/terms
      http://checkout.merchant.se/terms
    ]

    expect(invalid_urls).to all(satisfy { |url| !described_class.valid_https?(url) })
    expect(described_class.valid_https?("https://checkout.merchant.se/store", origin: true)).to be(false)
  end
end
