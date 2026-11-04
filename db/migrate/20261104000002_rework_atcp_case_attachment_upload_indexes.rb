# frozen_string_literal: true

class ReworkAtcpCaseAttachmentUploadIndexes < ActiveRecord::Migration[8.0]
  ACTIVE_INDEX = "index_atcp_case_attachments_on_update_id_and_upload_id_active"

  def up
    remove_index :atcp_case_attachments, :upload_id
    add_index :atcp_case_attachments, :upload_id
    add_index :atcp_case_attachments,
              %i[update_id upload_id],
              unique: true,
              where: "deleted_at IS NULL",
              name: ACTIVE_INDEX
  end

  def down
    reused_upload_ids =
      DB.query_single(
        "SELECT upload_id FROM atcp_case_attachments GROUP BY upload_id HAVING COUNT(*) > 1"
      )

    if reused_upload_ids.present?
      raise ActiveRecord::IrreversibleMigration,
            "Cannot restore the unique index on upload_id: uploads are attached more than once " \
              "(upload_id: #{reused_upload_ids.first(20).inspect})"
    end

    remove_index :atcp_case_attachments, name: ACTIVE_INDEX
    remove_index :atcp_case_attachments, :upload_id
    add_index :atcp_case_attachments, :upload_id, unique: true
  end
end
