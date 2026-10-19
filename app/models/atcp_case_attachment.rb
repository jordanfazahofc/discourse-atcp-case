# frozen_string_literal: true

class AtcpCaseAttachment < ActiveRecord::Base
  self.table_name = "atcp_case_attachments"

  belongs_to :atcp_case, foreign_key: :case_id
  belongs_to :atcp_case_update, foreign_key: :update_id
  belongs_to :upload
end
