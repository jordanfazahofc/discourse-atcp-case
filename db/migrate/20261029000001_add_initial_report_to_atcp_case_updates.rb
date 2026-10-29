# frozen_string_literal: true

class AddInitialReportToAtcpCaseUpdates < ActiveRecord::Migration[8.0]
  def change
    add_column :atcp_case_updates,
               :initial_report,
               :boolean,
               null: false,
               default: false
  end
end
