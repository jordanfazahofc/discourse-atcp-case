# frozen_string_literal: true

RSpec.describe AtcpCaseUpdate do
  fab!(:admin)
  fab!(:case_record, :atcp_case)

  describe "update_type validation" do
    it "accepts an arbitrary update type" do
      record =
        Fabricate.build(
          :atcp_case_update,
          atcp_case: case_record,
          update_type: "Escalated to vendor"
        )
      expect(record).to be_valid
    end

    it "accepts an update type at the maximum length" do
      record =
        Fabricate.build(
          :atcp_case_update,
          atcp_case: case_record,
          update_type: "x" * 100
        )
      expect(record).to be_valid
    end

    it "requires an update type for user entries" do
      record =
        Fabricate.build(
          :atcp_case_update,
          atcp_case: case_record,
          update_type: nil
        )
      expect(record).to be_invalid
      expect(record.errors[:update_type]).to be_present
    end

    it "rejects an update type longer than 100 characters" do
      record =
        Fabricate.build(
          :atcp_case_update,
          atcp_case: case_record,
          update_type: "x" * 101
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

    it "does not revalidate an existing update type when the setting changes" do
      record =
        Fabricate(
          :atcp_case_update,
          atcp_case: case_record,
          update_type: "Custom historical type"
        )

      SiteSetting.atcp_case_update_labels = "Testing|Waiting for unit"

      record.update!(body: "Still allowed to update the body")

      expect(record.reload.update_type).to eq("Custom historical type")
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
