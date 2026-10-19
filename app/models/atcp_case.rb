# frozen_string_literal: true

class AtcpCase < ActiveRecord::Base
  self.table_name = "atcp_cases"

  CASE_TYPES = [
    "Hardware defect",
    "Compatibility",
    "BIOS/Firmware",
    "Driver/Software",
    "Performance",
    "Other"
  ].freeze
  SEVERITIES = %w[Low Medium High Critical].freeze
  STATUSES = [
    "Open",
    "In Progress",
    "On Hold",
    "Solution Found",
    "Closed"
  ].freeze
  CLOSE_REASONS = [
    "Resolved",
    "Duplicate",
    "Cannot Reproduce",
    "Won't Fix",
    "Cancelled"
  ].freeze
  FREQUENCIES = ["Intermittent", "Always", "Specific conditions"].freeze
  REPRODUCIBILITIES = ["Reproducible", "Not reproducible", "Not tried"].freeze

  has_many :atcp_case_products, foreign_key: :case_id
  has_many :atcp_case_updates, foreign_key: :case_id
  has_many :atcp_case_attachments, foreign_key: :case_id

  belongs_to :created_by, class_name: "User", foreign_key: :created_by_id
  belongs_to :assignee,
             class_name: "User",
             foreign_key: :assignee_id,
             optional: true

  validates :case_number, :title, :symptom, presence: true
  validates :source, presence: true, length: { maximum: 255 }
  validates :case_type, inclusion: { in: CASE_TYPES }
  validates :severity, inclusion: { in: SEVERITIES }
  validates :status, inclusion: { in: STATUSES }
  validates :frequency, inclusion: { in: FREQUENCIES }, allow_nil: true
  validates :reproducibility,
            inclusion: {
              in: REPRODUCIBILITIES
            },
            allow_nil: true
  validates :close_reason, inclusion: { in: CLOSE_REASONS }, allow_nil: true

  validate :close_reason_required_when_closed
  validate :solution_required_when_resolved

  before_validation :ensure_opened_at

  # CASE-2026-0001: counter per tahun diambil dari nomor tertinggi yang ada,
  # bukan COUNT(*), supaya baris yang hilang di tengah tidak membuat tabrakan.
  def self.next_case_number
    year = Time.now.in_time_zone("Asia/Jakarta").year
    prefix = "CASE-#{year}-"
    max_seq =
      where("case_number LIKE ?", "#{prefix}%")
        .pluck(:case_number)
        .filter_map { |number| number[/\A#{prefix}(\d+)\z/, 1]&.to_i }
        .max || 0
    format("CASE-%<year>d-%<seq>04d", year: year, seq: max_seq + 1)
  end

  # Unique index case_number adalah pengaman terakhir; bila ada request balapan
  # yang kalah, generate ulang nomor dan coba lagi.
  def self.create_with_generated_number!(attrs = {}, max_attempts: 3)
    attempt = 0

    begin
      transaction(requires_new: true) do
        create!(attrs.merge(case_number: next_case_number))
      end
    rescue ActiveRecord::RecordNotUnique
      attempt += 1
      retry if attempt < max_attempts
      raise
    end
  end

  private

  def ensure_opened_at
    self.opened_at ||= Time.zone.now
  end

  def close_reason_required_when_closed
    return unless status == "Closed"
    return if close_reason.present?

    errors.add(:close_reason, :blank)
  end

  def solution_required_when_resolved
    return unless status == "Closed" && close_reason == "Resolved"
    return if solution.present?

    errors.add(:solution, :blank)
  end
end

# == Schema Information
#
# Table name: atcp_cases
#
#  id                     :bigint           not null, primary key
#  bios_version           :string
#  case_number            :string           not null
#  case_type              :string           not null
#  close_reason           :string
#  closed_at              :datetime
#  conclusion             :text
#  frequency              :string
#  non_trigger_conditions :text
#  opened_at              :datetime         not null
#  os_driver_info         :text
#  reporter_branch_name   :string
#  reporter_name          :string
#  reproducibility        :string
#  root_cause_summary     :text
#  severity               :string           not null
#  solution               :text
#  source                 :string           not null
#  status                 :string           default("Open"), not null
#  symptom                :text             not null
#  title                  :string           not null
#  workaround             :text
#  created_at             :datetime         not null
#  updated_at             :datetime         not null
#  assignee_id            :integer
#  created_by_id          :integer          not null
#  reporter_branch_id     :integer
#
# Indexes
#
#  index_atcp_cases_on_assignee_id         (assignee_id)
#  index_atcp_cases_on_case_number         (case_number) UNIQUE
#  index_atcp_cases_on_opened_at           (opened_at)
#  index_atcp_cases_on_reporter_branch_id  (reporter_branch_id)
#  index_atcp_cases_on_severity            (severity)
#  index_atcp_cases_on_status              (status)
#
# Foreign Keys
#
#  fk_rails_...  (assignee_id => users.id) ON DELETE => restrict
#  fk_rails_...  (created_by_id => users.id) ON DELETE => restrict
#
