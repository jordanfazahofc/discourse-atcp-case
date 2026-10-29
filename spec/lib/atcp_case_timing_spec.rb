# frozen_string_literal: true

require_relative "../../lib/atcp_case_timing"

RSpec.describe AtcpCaseTiming do
  fab!(:user)

  describe ".aging_days" do
    it "floors the days between opened_at and now" do
      atcp_case =
        Fabricate(:atcp_case, created_by: user, opened_at: 2.days.ago - 6.hours)

      expect(described_class.aging_days(atcp_case)).to eq(2)
    end

    it "uses closed_at once the case is closed" do
      atcp_case =
        Fabricate(
          :atcp_case,
          created_by: user,
          opened_at: 6.days.ago,
          status: "Closed",
          close_reason: "Duplicate",
          closed_at: 2.days.ago
        )

      expect(described_class.aging_days(atcp_case)).to eq(4)
    end
  end

  describe ".waiting" do
    it "returns the most recent waiting label of user updates" do
      atcp_case = Fabricate(:atcp_case, created_by: user)
      Fabricate(
        :atcp_case_update,
        atcp_case: atcp_case,
        user: user,
        update_type: "Waiting for unit",
        created_at: 4.days.ago
      )
      Fabricate(
        :atcp_case_update,
        atcp_case: atcp_case,
        user: user,
        update_type: "Waiting for vendor",
        created_at: 2.days.ago
      )

      waiting = described_class.waiting(atcp_case)

      expect(waiting[:label]).to eq("Waiting for vendor")
      expect(waiting[:since]).to be_within(1.second).of(2.days.ago)
      expect(waiting[:days]).to eq(2)
    end

    it "detects waiting labels case-insensitively and ignores leading spaces" do
      atcp_case = Fabricate(:atcp_case, created_by: user)
      Fabricate(
        :atcp_case_update,
        atcp_case: atcp_case,
        user: user,
        update_type: "  waitING FOR vendor  ",
        created_at: 2.days.ago
      )

      waiting = described_class.waiting(atcp_case)

      expect(waiting[:label]).to eq("  waitING FOR vendor  ")
      expect(waiting[:days]).to eq(2)
    end

    it "ignores system entries when looking for the last user label" do
      atcp_case = Fabricate(:atcp_case, created_by: user)
      Fabricate(
        :atcp_case_update,
        atcp_case: atcp_case,
        user: user,
        update_type: "Waiting for unit",
        created_at: 3.days.ago
      )
      Fabricate(
        :atcp_case_update,
        atcp_case: atcp_case,
        user: user,
        is_system: true,
        update_type: nil,
        system_event: "status_changed",
        from_value: "Open",
        to_value: "In Progress",
        created_at: 1.day.ago
      )

      expect(described_class.waiting(atcp_case)[:label]).to eq(
        "Waiting for unit"
      )
    end

    it "returns nil when the last user label is not a waiting label" do
      atcp_case = Fabricate(:atcp_case, created_by: user)
      Fabricate(
        :atcp_case_update,
        atcp_case: atcp_case,
        user: user,
        update_type: "General note",
        created_at: 1.day.ago
      )

      expect(described_class.waiting(atcp_case)).to be_nil
    end

    it "returns nil for closed cases" do
      atcp_case =
        Fabricate(
          :atcp_case,
          created_by: user,
          status: "Closed",
          close_reason: "Duplicate",
          closed_at: 1.day.ago
        )
      Fabricate(
        :atcp_case_update,
        atcp_case: atcp_case,
        user: user,
        update_type: "Waiting for unit",
        created_at: 2.days.ago
      )

      expect(described_class.waiting(atcp_case)).to be_nil
    end

    it "returns nil when there is no user update" do
      atcp_case = Fabricate(:atcp_case, created_by: user)

      expect(described_class.waiting(atcp_case)).to be_nil
    end

    it "does not treat an initial report as waiting or change aging" do
      atcp_case =
        Fabricate(:atcp_case, created_by: user, opened_at: 2.days.ago - 6.hours)
      Fabricate(
        :atcp_case_update,
        atcp_case: atcp_case,
        user: user,
        update_type: AtcpCaseUpdate::INITIAL_REPORT_TYPE,
        body: nil,
        initial_report: true,
        created_at: 2.days.ago
      )

      expect(described_class.waiting(atcp_case)).to be_nil
      expect(described_class.aging_days(atcp_case)).to eq(2)
    end
  end
end
