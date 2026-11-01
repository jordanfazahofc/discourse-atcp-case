# frozen_string_literal: true

class RemoveSeverityAndReproducibilityFromAtcpCases < ActiveRecord::Migration[
  8.0
]
  def up
    remove_index :atcp_cases, :severity, if_exists: true
    remove_column :atcp_cases, :severity, :string
    remove_column :atcp_cases, :reproducibility, :string
  end

  def down
    add_column :atcp_cases, :severity, :string
    add_column :atcp_cases, :reproducibility, :string
  end
end
