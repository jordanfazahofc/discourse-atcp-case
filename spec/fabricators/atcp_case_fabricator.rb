# frozen_string_literal: true

Fabricator(:atcp_case, from: "AtcpCase") do
  case_number do
    sequence(:atcp_case_number) do |i|
      format("CASE-%<year>d-%<seq>04d", year: Time.zone.now.year, seq: i)
    end
  end
  title { sequence(:atcp_case_title) { |i| "Test case #{i}" } }
  case_type "Hardware defect"
  severity "Medium"
  status "Open"
  source "manual"
  reporter_name { sequence(:atcp_case_reporter) { |i| "Reporter #{i}" } }
  symptom "Device does not boot after BIOS update"
  created_by { Fabricate(:user) }
  opened_at { Time.zone.now }
end

Fabricator(:atcp_case_product, from: "AtcpCaseProduct") do
  atcp_case
  atcp_product { Fabricate(:atcp_product) }
end

Fabricator(:atcp_case_update, from: "AtcpCaseUpdate") do
  atcp_case
  user { Fabricate(:user) }
  update_type "General note"
  body { sequence(:atcp_case_update_body) { |i| "Case update #{i}" } }
end
