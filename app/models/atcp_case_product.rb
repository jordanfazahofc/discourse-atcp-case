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

# == Schema Information
#
# Table name: atcp_case_products
#
#  id           :bigint           not null, primary key
#  product_name :string           not null
#  sku_code     :string
#  created_at   :datetime         not null
#  updated_at   :datetime         not null
#  case_id      :integer          not null
#  product_id   :integer
#
# Indexes
#
#  index_atcp_case_products_on_case_id                 (case_id)
#  index_atcp_case_products_on_case_id_and_product_id  (case_id,product_id) UNIQUE
#  index_atcp_case_products_on_product_id              (product_id)
#
# Foreign Keys
#
#  fk_rails_...  (case_id => atcp_cases.id) ON DELETE => cascade
#  fk_rails_...  (product_id => atcp_products.id) ON DELETE => nullify
#
