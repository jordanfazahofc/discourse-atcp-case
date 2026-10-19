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

  validates :system_event, inclusion: { in: SYSTEM_EVENTS }, allow_nil: true
  validate :update_type_allowed

  default_scope { where(deleted_at: nil) } # ODM-003
  scope :with_deleted, -> { unscope(where: :deleted_at) }

  def soft_delete!(actor)
    update!(deleted_at: Time.zone.now, deleted_by_id: actor.id)
  end

  private

  def update_type_allowed
    return if is_system
    return unless new_record? || will_save_change_to_update_type?

    if update_type.blank?
      errors.add(:update_type, :blank)
    elsif SiteSetting.atcp_case_update_labels.split("|").exclude?(update_type)
      errors.add(:update_type, :inclusion)
    end
  end
end

# == Schema Information
#
# Table name: atcp_case_updates
#
#  id            :bigint           not null, primary key
#  body          :text
#  deleted_at    :datetime
#  details       :jsonb            not null
#  edited_at     :datetime
#  from_value    :string
#  is_system     :boolean          default(FALSE), not null
#  system_event  :string
#  to_value      :string
#  update_type   :string
#  created_at    :datetime         not null
#  updated_at    :datetime         not null
#  case_id       :integer          not null
#  deleted_by_id :integer
#  user_id       :integer          not null
#
# Indexes
#
#  index_atcp_case_updates_on_case_id     (case_id)
#  index_atcp_case_updates_on_deleted_at  (deleted_at)
#
# Foreign Keys
#
#  fk_rails_...  (case_id => atcp_cases.id) ON DELETE => cascade
#  fk_rails_...  (user_id => users.id) ON DELETE => restrict
#
