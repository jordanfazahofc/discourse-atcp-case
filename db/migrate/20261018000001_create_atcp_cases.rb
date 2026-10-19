# frozen_string_literal: true

class CreateAtcpCases < ActiveRecord::Migration[8.0]
  def change
    create_table :atcp_cases do |t|
      t.string :case_number, null: false
      t.string :title, null: false
      t.string :case_type, null: false
      t.string :severity, null: false
      t.string :status, null: false, default: "Open"
      t.string :source, null: false
      t.string :reporter_name
      # snapshot cabang: tanpa FK supaya riwayat tetap utuh walau branch dihapus
      t.integer :reporter_branch_id
      t.string :reporter_branch_name
      t.text :symptom, null: false
      t.string :frequency
      t.string :reproducibility
      t.text :non_trigger_conditions
      t.string :bios_version
      t.text :os_driver_info
      t.text :root_cause_summary
      t.text :solution
      t.text :workaround
      t.text :conclusion
      t.string :close_reason
      t.integer :assignee_id
      t.datetime :opened_at, null: false
      t.datetime :closed_at
      t.integer :created_by_id, null: false

      t.timestamps
    end

    add_index :atcp_cases, :case_number, unique: true
    add_index :atcp_cases, :status
    add_index :atcp_cases, :severity
    add_index :atcp_cases, :opened_at
    add_index :atcp_cases, :assignee_id
    add_index :atcp_cases, :reporter_branch_id

    add_foreign_key :atcp_cases,
                    :users,
                    column: :assignee_id,
                    on_delete: :restrict
    add_foreign_key :atcp_cases,
                    :users,
                    column: :created_by_id,
                    on_delete: :restrict
  end
end
