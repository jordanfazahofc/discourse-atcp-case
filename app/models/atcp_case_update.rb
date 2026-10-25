# frozen_string_literal: true

class AtcpCaseUpdate < ActiveRecord::Base
  self.table_name = "atcp_case_updates"

  SYSTEM_EVENTS = %w[
    status_changed
    severity_changed
    assignee_changed
    closed
    reopened
  ].freeze

  belongs_to :atcp_case, foreign_key: :case_id
  belongs_to :user
  belongs_to :deleted_by,
             class_name: "User",
             foreign_key: :deleted_by_id,
             optional: true

  has_many :atcp_case_attachments, foreign_key: :update_id

  validates :system_event, inclusion: { in: SYSTEM_EVENTS }, allow_nil: true
  validates :update_type,
            presence: true,
            length: {
              maximum: 100
            },
            unless: :is_system

  default_scope { where(deleted_at: nil) } # ODM-003
  scope :with_deleted, -> { unscope(where: :deleted_at) }

  def soft_delete!(actor)
    update!(deleted_at: Time.zone.now, deleted_by_id: actor.id)
  end
end
