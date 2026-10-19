# frozen_string_literal: true

class CreateAtcpCaseUpdates < ActiveRecord::Migration[8.0]
  def change
    create_table :atcp_case_updates do |t|
      t.integer :case_id, null: false
      t.integer :user_id, null: false
      t.string :update_type
      t.text :body
      t.boolean :is_system, null: false, default: false
      t.string :system_event
      t.string :from_value
      t.string :to_value
      t.jsonb :details, null: false, default: {}
      t.datetime :edited_at
      t.datetime :deleted_at
      t.integer :deleted_by_id

      t.timestamps
    end

    add_index :atcp_case_updates, :case_id
    add_index :atcp_case_updates, :deleted_at

    add_foreign_key :atcp_case_updates,
                    :atcp_cases,
                    column: :case_id,
                    on_delete: :cascade
    add_foreign_key :atcp_case_updates,
                    :users,
                    column: :user_id,
                    on_delete: :restrict
  end
end
