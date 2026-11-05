# frozen_string_literal: true

RSpec.describe AtcpCaseProductLabel do
  it "keeps the name when the SKU is blank" do
    expect(AtcpCaseProductLabel.label("Axioo P15", nil)).to eq("Axioo P15")
    expect(AtcpCaseProductLabel.label("Axioo P15", "  ")).to eq("Axioo P15")
  end

  it "does not repeat a SKU already present in the name" do
    expect(
      AtcpCaseProductLabel.label("Axioo P15 AXIOO-P15", "AXIOO-P15")
    ).to eq("Axioo P15 AXIOO-P15")
    expect(
      AtcpCaseProductLabel.label("Axioo P15 axioo-p15", "AXIOO-P15")
    ).to eq("Axioo P15 axioo-p15")
  end

  it "appends the SKU when the name does not contain it" do
    expect(AtcpCaseProductLabel.label("Axioo P15", "AXIOO-P15")).to eq(
      "Axioo P15 (AXIOO-P15)"
    )
  end
end
