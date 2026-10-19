# frozen_string_literal: true

class AtcpCaseListItemSerializer < ApplicationSerializer
  attributes :id,
             :case_number,
             :title,
             :products,
             :severity,
             :status,
             :assignee,
             :aging_days,
             :waiting

  def products
    object.atcp_case_products.map do |entry|
      { id: entry.product_id, name: entry.product_name, sku: entry.sku_code }
    end
  end

  def assignee
    user = object.assignee
    return nil if user.nil?

    { id: user.id, username: user.username, name: user.name }
  end

  def aging_days
    AtcpCaseTiming.aging_days(object)
  end

  def waiting
    AtcpCaseTiming.waiting(object)
  end
end
