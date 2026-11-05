# frozen_string_literal: true

# Regresi: index tidak boleh memuat produk secara parsial saat difilter product_id.
# Sebelum perbaikan, includes(:atcp_case_products) + joins(:atcp_case_products)
# dengan kondisi hash membuat eager load hanya menyimpan baris produk yang cocok
# filter, sehingga daftar tampil satu produk padahal kasus punya dua.
RSpec.describe "Atcp case index product filter regression" do
  fab!(:internal_group, :group)
  fab!(:internal_user, :user)

  before do
    enable_current_plugin
    internal_group.add(internal_user)
    SiteSetting.atcp_internal_groups = internal_group.id.to_s
  end

  def add_product!(atcp_case, name:, sku:)
    product = Fabricate(:atcp_product, sku_code: sku)
    Fabricate(
      :atcp_case_product,
      atcp_case: atcp_case,
      atcp_product: product,
      product_name: name,
      sku_code: sku
    )
    product
  end

  it "tampilkan semua produk kasus walau difilter satu produk" do
    atcp_case = Fabricate(:atcp_case, created_by: internal_user)
    first_product = add_product!(atcp_case, name: "Axioo P15", sku: "AXIOO-P15")
    add_product!(atcp_case, name: "Axioo P16", sku: "AXIOO-P16")

    sign_in(internal_user)
    get "/atcp/cases.json", params: { product_id: first_product.id }

    products = response.parsed_body["cases"].first["products"]
    expect(response.status).to eq(200)
    expect(products.map { |entry| entry["name"] }).to eq(
      ["Axioo P15", "Axioo P16"]
    )
  end

  it "tanpa filter produk tetap menampilkan semua produk kasus" do
    atcp_case = Fabricate(:atcp_case, created_by: internal_user)
    add_product!(atcp_case, name: "Axioo P15", sku: "AXIOO-P15")
    add_product!(atcp_case, name: "Axioo P16", sku: "AXIOO-P16")

    sign_in(internal_user)
    get "/atcp/cases.json"

    products = response.parsed_body["cases"].first["products"]
    expect(response.status).to eq(200)
    expect(products.map { |entry| entry["name"] }).to eq(
      ["Axioo P15", "Axioo P16"]
    )
  end

  it "total_count dan status_counts tidak berubah oleh filter produk" do
    atcp_case = Fabricate(:atcp_case, created_by: internal_user)
    first_product = add_product!(atcp_case, name: "Axioo P15", sku: "AXIOO-P15")
    add_product!(atcp_case, name: "Axioo P16", sku: "AXIOO-P16")

    sign_in(internal_user)

    get "/atcp/cases.json"
    total_count_all = response.parsed_body["total_count"]
    status_counts_all = response.parsed_body["status_counts"]

    get "/atcp/cases.json", params: { product_id: first_product.id }

    expect(response.parsed_body["total_count"]).to eq(total_count_all)
    expect(response.parsed_body["status_counts"]).to eq(status_counts_all)
    expect(response.parsed_body["cases"].size).to eq(1)
  end
end
