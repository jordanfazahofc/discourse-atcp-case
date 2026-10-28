# frozen_string_literal: true

class RemoveReporterFromAtcpCases < ActiveRecord::Migration[8.0]
  def change
    remove_index :atcp_cases, :reporter_branch_id, if_exists: true
    remove_column :atcp_cases, :reporter_name, :string
    remove_column :atcp_cases, :reporter_branch_id, :integer
    remove_column :atcp_cases, :reporter_branch_name, :string
  end
end
