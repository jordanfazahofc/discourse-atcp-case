# frozen_string_literal: true

class CreateAtcpCaseProducts < ActiveRecord::Migration[8.0]
  def change
    create_table :atcp_case_products do |t|
      t.integer :case_id, null: false
      t.integer :product_id
      t.string :product_name, null: false
      t.string :sku_code

      t.timestamps
    end

    add_index :atcp_case_products, :case_id
    add_index :atcp_case_products, :product_id
    add_index :atcp_case_products, %i[case_id product_id], unique: true

    add_foreign_key :atcp_case_products,
                    :atcp_cases,
                    column: :case_id,
                    on_delete: :cascade
    # nullify: baris ini adalah snapshot, case harus tetap hidup walau produk dihapus
    add_foreign_key :atcp_case_products,
                    :atcp_products,
                    column: :product_id,
                    on_delete: :nullify
  end
end
