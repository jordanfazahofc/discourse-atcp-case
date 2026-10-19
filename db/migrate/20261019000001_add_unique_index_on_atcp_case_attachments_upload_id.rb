# frozen_string_literal: true

class AddUniqueIndexOnAtcpCaseAttachmentsUploadId < ActiveRecord::Migration[8.0]
  def change
    add_index :atcp_case_attachments, :upload_id, unique: true
  end
end
