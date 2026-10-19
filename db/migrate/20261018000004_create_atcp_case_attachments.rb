# frozen_string_literal: true

class CreateAtcpCaseAttachments < ActiveRecord::Migration[8.0]
  def change
    create_table :atcp_case_attachments do |t|
      t.integer :case_id, null: false
      t.integer :update_id, null: false
      t.integer :upload_id, null: false

      t.datetime :created_at, null: false
    end

    add_index :atcp_case_attachments, :case_id
    add_index :atcp_case_attachments, :update_id

    add_foreign_key :atcp_case_attachments,
                    :atcp_cases,
                    column: :case_id,
                    on_delete: :cascade
    add_foreign_key :atcp_case_attachments,
                    :atcp_case_updates,
                    column: :update_id,
                    on_delete: :cascade
    add_foreign_key :atcp_case_attachments,
                    :uploads,
                    column: :upload_id,
                    on_delete: :restrict
  end
end
