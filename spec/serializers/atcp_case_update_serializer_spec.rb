# frozen_string_literal: true

RSpec.describe AtcpCaseUpdateSerializer do
  fab!(:author, :user)
  fab!(:other_user, :user)
  fab!(:admin, :admin)
  fab!(:atcp_case) { Fabricate(:atcp_case, created_by: author) }
  fab!(:entry) do
    Fabricate(:atcp_case_update, atcp_case: atcp_case, user: author)
  end

  def serialize(record, user)
    described_class.new(record, scope: Guardian.new(user), root: false).as_json
  end

  it "allows the author to edit and delete their own entry" do
    json = serialize(entry, author)

    expect(json).to include(can_edit: true, can_delete: true)
  end

  it "forbids another member from editing or deleting the entry" do
    json = serialize(entry, other_user)

    expect(json).to include(can_edit: false, can_delete: false)
  end

  it "allows an admin to edit and delete another user's entry" do
    json = serialize(entry, admin)

    expect(json).to include(can_edit: true, can_delete: true)
  end

  it "ignores the closed case status" do
    atcp_case.update!(
      status: "Closed",
      close_reason: "Duplicate",
      closed_at: 1.hour.ago
    )

    json = serialize(entry, author)

    expect(json).to include(can_edit: true, can_delete: true)
  end

  it "allows an admin to edit and delete a system entry" do
    system_entry =
      Fabricate(
        :atcp_case_update,
        atcp_case: atcp_case,
        user: author,
        is_system: true,
        update_type: nil,
        system_event: "status_changed"
      )

    json = serialize(system_entry, admin)

    expect(json).to include(can_edit: true, can_delete: true)
  end

  it "only allows admins to delete an initial report" do
    initial_report =
      Fabricate(
        :atcp_case_update,
        atcp_case: atcp_case,
        user: author,
        update_type: AtcpCaseUpdate::INITIAL_REPORT_TYPE,
        body: nil,
        initial_report: true
      )

    expect(serialize(initial_report, author)).to include(
      can_edit: true,
      can_delete: false,
      initial_report: true
    )
    expect(serialize(initial_report, other_user)).to include(
      can_edit: false,
      can_delete: false
    )
    expect(serialize(initial_report, admin)).to include(
      can_edit: true,
      can_delete: true
    )
  end
end
