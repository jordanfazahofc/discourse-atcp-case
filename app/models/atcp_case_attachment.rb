# frozen_string_literal: true

class AtcpCaseAttachment < ActiveRecord::Base
  self.table_name = "atcp_case_attachments"

  belongs_to :atcp_case, foreign_key: :case_id
  belongs_to :atcp_case_update, foreign_key: :update_id
  belongs_to :upload
  belongs_to :deleted_by,
             class_name: "User",
             foreign_key: :deleted_by_id,
             optional: true

  # Melindungi upload dari pembersih upload yatim Discourse. Ref sengaja
  # tidak dihapus saat entri di-soft-delete (ODM-003: histori tetap ada).
  after_create :register_upload_reference

  default_scope { where(deleted_at: nil) } # ODM-003
  scope :with_deleted, -> { unscope(where: :deleted_at) }

  def soft_delete!(actor)
    update!(deleted_at: Time.zone.now, deleted_by_id: actor.id)
  end

  private

  def register_upload_reference
    UploadReference.ensure_exist!(upload_ids: [upload_id], target: self)
  end
end
