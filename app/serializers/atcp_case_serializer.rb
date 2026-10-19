# frozen_string_literal: true

class AtcpCaseSerializer < ApplicationSerializer
  attributes :id,
             :case_number,
             :title,
             :case_type,
             :severity,
             :status,
             :source,
             :reporter_name,
             :reporter_branch_id,
             :reporter_branch_name,
             :symptom,
             :frequency,
             :reproducibility,
             :non_trigger_conditions,
             :bios_version,
             :os_driver_info,
             :root_cause_summary,
             :solution,
             :workaround,
             :conclusion,
             :close_reason,
             :opened_at,
             :closed_at,
             :created_at,
             :updated_at,
             :products,
             :assignee,
             :created_by,
             :aging_days,
             :waiting,
             :updates

  def products
    object.atcp_case_products.map do |entry|
      { id: entry.product_id, name: entry.product_name, sku: entry.sku_code }
    end
  end

  def assignee
    user_summary(object.assignee)
  end

  def created_by
    user_summary(object.created_by)
  end

  def aging_days
    AtcpCaseTiming.aging_days(object)
  end

  def waiting
    AtcpCaseTiming.waiting(object)
  end

  def updates
    object
      .atcp_case_updates
      .sort_by { |update| [update.created_at, update.id] }
      .reverse
      .map do |update|
        AtcpCaseUpdateSerializer.new(update, root: false).as_json
      end
  end

  private

  def user_summary(user)
    return nil if user.nil?

    { id: user.id, username: user.username, name: user.name }
  end
end
