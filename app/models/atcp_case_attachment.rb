# frozen_string_literal: true

class AtcpCaseAttachment < ActiveRecord::Base
  self.table_name = "atcp_case_attachments"

  belongs_to :atcp_case, foreign_key: :case_id
  belongs_to :atcp_case_update, foreign_key: :update_id
  belongs_to :upload

  # Melindungi upload dari pembersih upload yatim Discourse. Ref sengaja
  # tidak dihapus saat entri di-soft-delete (ODM-003: histori tetap ada).
  after_create :register_upload_reference

  private

  def register_upload_reference
    UploadReference.ensure_exist!(upload_ids: [upload_id], target: self)
  end
end
