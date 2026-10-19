# frozen_string_literal: true

RSpec.describe "Atcp case attachment upload protection" do
  fab!(:internal_group, :group)
  fab!(:internal_user, :user)
  fab!(:atcp_case) { Fabricate(:atcp_case, created_by: internal_user) }

  before do
    enable_current_plugin
    internal_group.add(internal_user)
    SiteSetting.atcp_internal_groups = internal_group.id.to_s
    SiteSetting.clean_up_uploads = true
    SiteSetting.clean_orphan_uploads_grace_period_hours = 1
    Jobs::CleanUpUploads.new.reset_last_cleanup!
    sign_in(internal_user)
  end

  def pdf_upload(user = internal_user)
    upload = Fabricate(:upload, user: user)
    upload.update_columns(original_filename: "evidence.pdf", extension: "pdf")
    upload
  end

  def attach_upload(upload)
    post "/atcp/cases/#{atcp_case.id}/updates.json",
         params: {
           update_type: "General note",
           body: "Checked the unit",
           upload_ids: [upload.id]
         }
    expect(response.status).to eq(200)
  end

  it "keeps uploads attached to a case when the orphan cleanup runs" do
    attached = pdf_upload
    control = pdf_upload
    attach_upload(attached)

    expect(
      UploadReference.exists?(
        upload_id: attached.id,
        target_type: "AtcpCaseAttachment"
      )
    ).to eq(true)

    freeze_time 2.hours.from_now
    Jobs::CleanUpUploads.new.execute(nil)

    expect(Upload.exists?(id: attached.id)).to eq(true)
    expect(Upload.exists?(id: control.id)).to eq(false)
  end

  it "deletes an identical unattached upload (control)" do
    control = pdf_upload

    freeze_time 2.hours.from_now
    Jobs::CleanUpUploads.new.execute(nil)

    expect(Upload.exists?(id: control.id)).to eq(false)
  end

  it "keeps uploads attached to a soft-deleted entry" do
    attached = pdf_upload
    control = pdf_upload
    attach_upload(attached)

    entry = AtcpCaseUpdate.where(case_id: atcp_case.id).order(:id).last
    entry.soft_delete!(internal_user)
    expect(entry.reload.deleted_at).to be_present

    freeze_time 2.hours.from_now
    Jobs::CleanUpUploads.new.execute(nil)

    expect(Upload.exists?(id: attached.id)).to eq(true)
    expect(Upload.exists?(id: control.id)).to eq(false)
    expect(AtcpCaseAttachment.exists?(upload_id: attached.id)).to eq(true)
    expect(
      UploadReference.exists?(
        upload_id: attached.id,
        target_type: "AtcpCaseAttachment"
      )
    ).to eq(true)
  end
end
