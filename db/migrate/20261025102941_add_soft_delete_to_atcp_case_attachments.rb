# frozen_string_literal: true

class AddSoftDeleteToAtcpCaseAttachments < ActiveRecord::Migration[8.0]
  def change
    add_column :atcp_case_attachments, :deleted_at, :datetime
    add_column :atcp_case_attachments, :deleted_by_id, :integer

    add_index :atcp_case_attachments, :deleted_at
  end
end
