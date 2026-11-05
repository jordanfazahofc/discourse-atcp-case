# frozen_string_literal: true

# Aturan label yang sama dengan helper UI productLabel di
# assets/javascripts/discourse/lib/atcp-case-detail.js.
module AtcpCaseProductLabel
  module_function

  def label(name, sku_code)
    product_name = name.to_s
    sku = sku_code.to_s.strip
    if sku.empty? || product_name.downcase.include?(sku.downcase)
      return product_name
    end

    "#{product_name} (#{sku})"
  end
end
