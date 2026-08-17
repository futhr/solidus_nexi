# frozen_string_literal: true

RSpec.describe SolidusNexi::Nexi::Money do
  describe ".to_minor" do
    it "converts decimal values without Float arithmetic" do
      expect(described_class.to_minor(BigDecimal("9.99"), "EUR")).to eq(999)
    end

    it "rejects precision that Nexi cannot represent" do
      expect { described_class.to_minor("1.001", "SEK") }
        .to raise_error(SolidusNexi::Nexi::ValidationError, /two decimal/)
    end

    it "rejects unsupported currencies" do
      expect { described_class.to_minor("10.00", "JPY") }
        .to raise_error(SolidusNexi::Nexi::ValidationError, /currency/)
    end

    it "rejects non-decimal and out-of-range values" do
      expect { described_class.to_minor("not-money", "SEK") }
        .to raise_error(SolidusNexi::Nexi::ValidationError, /decimal/)
      expect { described_class.to_minor(BigDecimal("21474836.48"), "SEK") }
        .to raise_error(SolidusNexi::Nexi::ValidationError, /32-bit/)
    end
  end

  describe ".validate_minor!" do
    it "accepts positive 32-bit integers only" do
      expect(described_class.validate_minor!(1)).to eq(1)
      [0, -1, 1.5, 2_147_483_648].each do |invalid|
        expect { described_class.validate_minor!(invalid) }
          .to raise_error(SolidusNexi::Nexi::ValidationError, /positive 32-bit/)
      end
    end
  end
end
