# frozen_string_literal: true

RSpec.describe AtcpCaseAttachment do
  fab!(:internal_user, :user)
  fab!(:case_record, :atcp_case)

  describe "unique index on (update_id, upload_id) for active rows" do
    it "rejects two active rows with the same update_id and upload_id" do
      upload = Fabricate(:upload, user: internal_user)
      entry =
        Fabricate(
          :atcp_case_update,
          atcp_case: case_record,
          user: internal_user
        )

      AtcpCaseAttachment.create!(
        case_id: case_record.id,
        update_id: entry.id,
        upload_id: upload.id
      )

      expect {
        AtcpCaseAttachment.create!(
          case_id: case_record.id,
          update_id: entry.id,
          upload_id: upload.id
        )
      }.to raise_error(ActiveRecord::RecordNotUnique)
    end

    it "allows two rows with the same update_id and upload_id when one is soft-deleted" do
      upload = Fabricate(:upload, user: internal_user)
      entry =
        Fabricate(
          :atcp_case_update,
          atcp_case: case_record,
          user: internal_user
        )

      first =
        AtcpCaseAttachment.create!(
          case_id: case_record.id,
          update_id: entry.id,
          upload_id: upload.id
        )
      first.soft_delete!(internal_user)

      expect {
        AtcpCaseAttachment.create!(
          case_id: case_record.id,
          update_id: entry.id,
          upload_id: upload.id
        )
      }.not_to raise_error
    end

    it "allows the same upload_id on different update_ids" do
      upload = Fabricate(:upload, user: internal_user)
      entry1 =
        Fabricate(
          :atcp_case_update,
          atcp_case: case_record,
          user: internal_user
        )
      entry2 =
        Fabricate(
          :atcp_case_update,
          atcp_case: case_record,
          user: internal_user
        )

      AtcpCaseAttachment.create!(
        case_id: case_record.id,
        update_id: entry1.id,
        upload_id: upload.id
      )

      expect {
        AtcpCaseAttachment.create!(
          case_id: case_record.id,
          update_id: entry2.id,
          upload_id: upload.id
        )
      }.not_to raise_error
    end
  end

  describe "#soft_delete!" do
    it "marks the row deleted without destroying Upload or UploadReference" do
      upload = Fabricate(:upload, user: internal_user)
      entry =
        Fabricate(
          :atcp_case_update,
          atcp_case: case_record,
          user: internal_user
        )
      attachment =
        AtcpCaseAttachment.create!(
          case_id: case_record.id,
          update_id: entry.id,
          upload_id: upload.id
        )

      attachment.soft_delete!(internal_user)

      expect(attachment.reload.deleted_at).to be_present
      expect(Upload.exists?(upload.id)).to eq(true)
      expect(
        UploadReference.exists?(
          upload_id: upload.id,
          target_type: "AtcpCaseAttachment"
        )
      ).to eq(true)
    end

    it "keeps the upload, its references, and other attachments of the same upload intact" do
      upload = Fabricate(:upload, user: internal_user)
      entry1 =
        Fabricate(
          :atcp_case_update,
          atcp_case: case_record,
          user: internal_user
        )
      entry2 =
        Fabricate(
          :atcp_case_update,
          atcp_case: case_record,
          user: internal_user
        )
      first =
        AtcpCaseAttachment.create!(
          case_id: case_record.id,
          update_id: entry1.id,
          upload_id: upload.id
        )
      second =
        AtcpCaseAttachment.create!(
          case_id: case_record.id,
          update_id: entry2.id,
          upload_id: upload.id
        )

      first.soft_delete!(internal_user)

      expect(second.reload.deleted_at).to be_nil
      expect(Upload.exists?(upload.id)).to eq(true)
      expect(
        UploadReference.exists?(
          upload_id: upload.id,
          target_type: "AtcpCaseAttachment",
          target_id: second.id
        )
      ).to eq(true)
    end
  end
end
