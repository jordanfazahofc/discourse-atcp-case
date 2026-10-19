# frozen_string_literal: true

RSpec.describe AtcpCaseUpdate do
  fab!(:admin)
  fab!(:case_record, :atcp_case)

  describe "update_type validation" do
    it "accepts a label from the configured list" do
      record =
        Fabricate.build(
          :atcp_case_update,
          atcp_case: case_record,
          update_type: "General note"
        )
      expect(record).to be_valid
    end

    it "rejects a label outside the configured list" do
      record =
        Fabricate.build(
          :atcp_case_update,
          atcp_case: case_record,
          update_type: "Made up"
        )
      expect(record).to be_invalid
      expect(record.errors[:update_type]).to be_present
    end

    it "rejects partial labels that only match as a substring" do
      partial_waiting =
        Fabricate.build(
          :atcp_case_update,
          atcp_case: case_record,
          update_type: "Waiting"
        )
      partial_general =
        Fabricate.build(
          :atcp_case_update,
          atcp_case: case_record,
          update_type: "General"
        )

      expect(partial_waiting).to be_invalid
      expect(partial_general).to be_invalid
    end

    it "follows the site setting when labels change" do
      SiteSetting.atcp_case_update_labels = "General note|Escalated to vendor"

      record =
        Fabricate.build(
          :atcp_case_update,
          atcp_case: case_record,
          update_type: "Escalated to vendor"
        )
      expect(record).to be_valid
    end

    it "requires a label for user entries" do
      record =
        Fabricate.build(
          :atcp_case_update,
          atcp_case: case_record,
          update_type: nil
        )
      expect(record).to be_invalid
      expect(record.errors[:update_type]).to be_present
    end

    it "allows system entries without a label" do
      record =
        Fabricate.build(
          :atcp_case_update,
          atcp_case: case_record,
          update_type: nil,
          is_system: true,
          system_event: "status_changed"
        )
      expect(record).to be_valid
    end

    it "rejects unknown system events" do
      record =
        Fabricate.build(
          :atcp_case_update,
          atcp_case: case_record,
          update_type: nil,
          is_system: true,
          system_event: "exploded"
        )
      expect(record).to be_invalid
      expect(record.errors[:system_event]).to be_present
    end

    it "skips label validation for existing entries when the label is removed from the setting" do
      record =
        Fabricate(
          :atcp_case_update,
          atcp_case: case_record,
          update_type: "General note"
        )

      SiteSetting.atcp_case_update_labels = "Testing|Waiting for unit"

      record.update!(body: "Still allowed to update the body")
      record.soft_delete!(admin)

      stored = AtcpCaseUpdate.with_deleted.find(record.id)
      expect(stored.deleted_at).to be_present
      expect(stored.body).to eq("Still allowed to update the body")
    end
  end

  describe "#soft_delete!" do
    it "hides the entry behind the default scope while keeping the row" do
      record = Fabricate(:atcp_case_update, atcp_case: case_record)

      record.soft_delete!(admin)

      expect(record.deleted_at).to be_present
      expect(record.deleted_by_id).to eq(admin.id)
      expect(AtcpCaseUpdate.where(id: record.id)).to be_blank
      expect(AtcpCaseUpdate.with_deleted.where(id: record.id)).to be_present
    end
  end
end
