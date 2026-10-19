# frozen_string_literal: true

class AtcpCaseProduct < ActiveRecord::Base
  self.table_name = "atcp_case_products"

  belongs_to :atcp_case, foreign_key: :case_id
  belongs_to :atcp_product, foreign_key: :product_id, optional: true

  validates :product_name, presence: true

  before_validation :snapshot_product

  private

  def snapshot_product
    return if atcp_product.blank?

    self.product_name = atcp_product.name if product_name.blank?
    self.sku_code = atcp_product.sku_code if sku_code.blank?
  end
end
