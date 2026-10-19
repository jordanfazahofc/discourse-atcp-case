# frozen_string_literal: true

RSpec.describe AtcpCaseProduct do
  fab!(:case_record, :atcp_case)

  it "snapshots product name and SKU code from the linked product" do
    product = Fabricate(:atcp_product)
    link =
      Fabricate(
        :atcp_case_product,
        atcp_case: case_record,
        atcp_product: product
      )

    expect(link.product_name).to eq(product.name)
    expect(link.sku_code).to eq(product.sku_code)
  end

  it "keeps an explicitly provided snapshot" do
    product = Fabricate(:atcp_product)

    link =
      Fabricate(
        :atcp_case_product,
        atcp_case: case_record,
        atcp_product: product,
        product_name: "Legacy name",
        sku_code: "LEGACY-1"
      )

    expect(link.product_name).to eq("Legacy name")
    expect(link.sku_code).to eq("LEGACY-1")
  end

  it "keeps the snapshot when the linked product is deleted" do
    product = Fabricate(:atcp_product)
    link =
      Fabricate(
        :atcp_case_product,
        atcp_case: case_record,
        atcp_product: product
      )
    snapshot_name = link.product_name

    product.destroy!

    link.reload
    expect(link.product_id).to be_nil
    expect(link.product_name).to eq(snapshot_name)
  end

  it "allows a manual product entry without a linked product" do
    link =
      Fabricate.build(
        :atcp_case_product,
        atcp_case: case_record,
        atcp_product: nil,
        product_name: "Manual entry"
      )
    expect(link).to be_valid
  end
end
