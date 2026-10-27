# frozen_string_literal: true

RSpec.describe "Atcp case updates" do
  fab!(:internal_group, :group)
  fab!(:internal_user, :user)
  fab!(:other_internal_user, :user)
  fab!(:outsider, :user)
  fab!(:moderator)
  fab!(:admin_user, :admin)
  fab!(:atcp_case) { Fabricate(:atcp_case, created_by: internal_user) }

  before do
    enable_current_plugin
    internal_group.add(internal_user)
    internal_group.add(other_internal_user)
    SiteSetting.atcp_internal_groups = internal_group.id.to_s
  end

  def entry_params(overrides = {})
    { update_type: "General note", body: "Checked the unit" }.merge(overrides)
  end

  def pdf_upload(user = internal_user, overrides = {})
    upload = Fabricate(:upload, user: user)
    upload.update_columns(
      { original_filename: "evidence.pdf", extension: "pdf" }.merge(overrides)
    )
    upload
  end

  def attach_upload(entry, upload)
    AtcpCaseAttachment.create!(
      case_id: entry.case_id,
      update_id: entry.id,
      upload_id: upload.id
    )
  end

  def system_entry(overrides = {})
    Fabricate(
      :atcp_case_update,
      {
        atcp_case: atcp_case,
        user: internal_user,
        is_system: true,
        update_type: nil,
        system_event: "status_changed",
        from_value: "Open",
        to_value: "In Progress"
      }.merge(overrides)
    )
  end

  describe "access guard" do
    it "blocks anonymous and non-internal users on every endpoint" do
      entry =
        Fabricate(:atcp_case_update, atcp_case: atcp_case, user: internal_user)

      [nil, outsider, moderator].each do |user|
        sign_in(user) if user

        post "/atcp/cases/#{atcp_case.id}/updates.json", params: entry_params
        expect(response.status).to eq(403)

        put "/atcp/cases/#{atcp_case.id}/updates/#{entry.id}.json",
            params: {
              body: "Nope"
            }
        expect(response.status).to eq(403)

        delete "/atcp/cases/#{atcp_case.id}/updates/#{entry.id}.json"
        expect(response.status).to eq(403)
      end
    end

    it "allows internal members to create, edit, and delete their own updates" do
      entry =
        Fabricate(:atcp_case_update, atcp_case: atcp_case, user: internal_user)
      sign_in(internal_user)

      post "/atcp/cases/#{atcp_case.id}/updates.json", params: entry_params
      expect(response.status).to eq(200)

      put "/atcp/cases/#{atcp_case.id}/updates/#{entry.id}.json",
          params: {
            body: "More details"
          }
      expect(response.status).to eq(200)

      delete "/atcp/cases/#{atcp_case.id}/updates/#{entry.id}.json"
      expect(response.status).to eq(204)
      expect(entry.reload.deleted_at).to be_present
      expect(entry.deleted_by_id).to eq(internal_user.id)
    end

    it "forbids another internal member before validating the edit" do
      entry =
        Fabricate(:atcp_case_update, atcp_case: atcp_case, user: internal_user)
      sign_in(other_internal_user)

      put "/atcp/cases/#{atcp_case.id}/updates/#{entry.id}.json", params: {}
      expect(response.status).to eq(403)

      delete "/atcp/cases/#{atcp_case.id}/updates/#{entry.id}.json"
      expect(response.status).to eq(403)
      expect(entry.reload.deleted_at).to be_nil
    end

    it "allows admins to delete updates with an audit log" do
      entry =
        Fabricate(:atcp_case_update, atcp_case: atcp_case, user: internal_user)
      sign_in(admin_user)

      delete "/atcp/cases/#{atcp_case.id}/updates/#{entry.id}.json"

      expect(response.status).to eq(204)
      entry.reload
      expect(entry.deleted_at).to be_present
      expect(entry.deleted_by_id).to eq(admin_user.id)

      audit =
        UserHistory
          .where(action: UserHistory.actions[:custom_staff])
          .order(:id)
          .last
      expect(audit.custom_type).to eq("atcp_case_update_deleted")
      expect(audit.details).to include("case_id: #{atcp_case.id}")
      expect(audit.details).to include("update_id: #{entry.id}")
    end
  end

  describe "#create" do
    before { sign_in(internal_user) }

    it "creates a note update" do
      post "/atcp/cases/#{atcp_case.id}/updates.json", params: entry_params

      expect(response.status).to eq(200)
      body = response.parsed_body
      expect(body["status"]).to eq("Open")

      update_json = body["update"]
      expect(update_json["update_type"]).to eq("General note")
      expect(update_json["body"]).to eq("Checked the unit")
      expect(update_json["is_system"]).to eq(false)
      expect(update_json["details"]).to eq({})
      expect(update_json["user"]["id"]).to eq(internal_user.id)
      expect(update_json["attachments"]).to eq([])

      entry = AtcpCaseUpdate.find(update_json["id"])
      expect(entry.case_id).to eq(atcp_case.id)
    end

    it "creates an update with attachments" do
      upload = pdf_upload

      post "/atcp/cases/#{atcp_case.id}/updates.json",
           params: entry_params(body: nil, upload_ids: [upload.id])

      expect(response.status).to eq(200)
      attachments = response.parsed_body["update"]["attachments"]
      expect(attachments.size).to eq(1)
      expect(attachments.first["id"]).to eq(
        AtcpCaseAttachment.find_by!(upload_id: upload.id).id
      )
      expect(attachments.first["upload_id"]).to eq(upload.id)
      expect(attachments.first["original_filename"]).to eq("evidence.pdf")
      expect(attachments.first["is_image"]).to eq(false)
      expect(
        AtcpCaseAttachment.exists?(case_id: atcp_case.id, upload_id: upload.id)
      ).to eq(true)
    end

    it "applies a status change with a system entry" do
      post "/atcp/cases/#{atcp_case.id}/updates.json",
           params: entry_params(status: "In Progress")

      expect(response.status).to eq(200)
      expect(response.parsed_body["status"]).to eq("In Progress")

      entries = AtcpCaseUpdate.where(case_id: atcp_case.id).order(:id)
      expect(entries.size).to eq(2)
      expect(entries.first.is_system).to eq(false)
      system_entry = entries.last
      expect(system_entry.is_system).to eq(true)
      expect(system_entry.system_event).to eq("status_changed")
      expect(system_entry.from_value).to eq("Open")
      expect(system_entry.to_value).to eq("In Progress")
      expect(atcp_case.reload.status).to eq("In Progress")
    end

    it "does not record a status entry when the status is unchanged" do
      post "/atcp/cases/#{atcp_case.id}/updates.json",
           params: entry_params(status: "Open")

      expect(response.status).to eq(200)
      expect(
        AtcpCaseUpdate.where(case_id: atcp_case.id, is_system: true).count
      ).to eq(0)
      expect(atcp_case.reload.status).to eq("Open")
    end

    it "rejects updates on a closed case" do
      closed =
        Fabricate(
          :atcp_case,
          created_by: internal_user,
          status: "Closed",
          close_reason: "Duplicate",
          closed_at: 1.hour.ago
        )

      post "/atcp/cases/#{closed.id}/updates.json", params: entry_params

      expect(response.status).to eq(422)
      expect(response.parsed_body["errors"]["base"]).to include(
        I18n.t("atcp_case.errors.case_closed")
      )
      expect(AtcpCaseUpdate.where(case_id: closed.id).count).to eq(0)
    end

    it "re-checks the closed status inside the lock" do
      stale = AtcpCase.find(atcp_case.id)
      atcp_case.update_columns(
        status: "Closed",
        close_reason: "Duplicate",
        closed_at: 1.hour.ago
      )
      allow_any_instance_of(Atcp::CaseUpdatesController).to receive(
        :find_case!
      ).and_return(stale)

      post "/atcp/cases/#{atcp_case.id}/updates.json", params: entry_params

      expect(response.status).to eq(422)
      expect(response.parsed_body["errors"]["base"]).to include(
        I18n.t("atcp_case.errors.case_closed")
      )
      expect(AtcpCaseUpdate.where(case_id: atcp_case.id).count).to eq(0)
    end

    it "rejects reusing an upload in a second entry" do
      upload = pdf_upload

      post "/atcp/cases/#{atcp_case.id}/updates.json",
           params: entry_params(body: nil, upload_ids: [upload.id])
      expect(response.status).to eq(200)

      post "/atcp/cases/#{atcp_case.id}/updates.json",
           params: entry_params(body: nil, upload_ids: [upload.id])

      expect(response.status).to eq(422)
      expect(response.parsed_body["errors"]["upload_ids"]).to include(
        I18n.t(
          "atcp_case.errors.attachment_already_used",
          filename: "evidence.pdf"
        )
      )
      expect(AtcpCaseUpdate.where(case_id: atcp_case.id).count).to eq(1)
    end

    it "rolls back the whole entry when the unique index rejects an upload" do
      upload = pdf_upload
      existing =
        Fabricate(:atcp_case_update, atcp_case: atcp_case, user: internal_user)
      AtcpCaseAttachment.create!(
        case_id: atcp_case.id,
        update_id: existing.id,
        upload_id: upload.id
      )
      allow(AtcpCaseAttachment).to receive(:exists?).and_call_original
      allow(AtcpCaseAttachment).to receive(:exists?).with(
        upload_id: upload.id
      ).and_return(false)

      post "/atcp/cases/#{atcp_case.id}/updates.json",
           params: entry_params(body: nil, upload_ids: [upload.id])

      expect(response.status).to eq(422)
      expect(response.parsed_body["errors"]["upload_ids"]).to include(
        I18n.t(
          "atcp_case.errors.attachment_already_used",
          filename: "evidence.pdf"
        )
      )
      expect(AtcpCaseUpdate.where(case_id: atcp_case.id).count).to eq(1)
      expect(AtcpCaseAttachment.count).to eq(1)
    end

    it "renders model validation errors with field messages" do
      record = AtcpCaseUpdate.new
      record.errors.add(:details, "is invalid")
      allow_any_instance_of(AtcpCaseUpdate).to receive(:save!).and_raise(
        ActiveRecord::RecordInvalid.new(record)
      )

      post "/atcp/cases/#{atcp_case.id}/updates.json", params: entry_params

      expect(response.status).to eq(422)
      expect(response.parsed_body["errors"]["details"]).to include("is invalid")
      expect(AtcpCaseUpdate.where(case_id: atcp_case.id).count).to eq(0)
    end

    it "accepts an arbitrary update type" do
      post "/atcp/cases/#{atcp_case.id}/updates.json",
           params: entry_params(update_type: "  Escalated to vendor  ")

      expect(response.status).to eq(200)
      expect(response.parsed_body["update"]["update_type"]).to eq(
        "Escalated to vendor"
      )
    end

    it "requires an update type" do
      post "/atcp/cases/#{atcp_case.id}/updates.json",
           params: entry_params(update_type: "   ")

      expect(response.status).to eq(422)
      expect(response.parsed_body["errors"]["update_type"]).to include(
        I18n.t("atcp_case.errors.update_type_required")
      )
      expect(AtcpCaseUpdate.where(case_id: atcp_case.id).count).to eq(0)
    end

    it "rejects an update type longer than 100 characters" do
      post "/atcp/cases/#{atcp_case.id}/updates.json",
           params: entry_params(update_type: "x" * 101)

      expect(response.status).to eq(422)
      expect(response.parsed_body["errors"]["update_type"]).to include(
        I18n.t("atcp_case.errors.update_type_too_long")
      )
      expect(AtcpCaseUpdate.where(case_id: atcp_case.id).count).to eq(0)
    end

    it "accepts an update type not present in the old suggestions" do
      post "/atcp/cases/#{atcp_case.id}/updates.json",
           params: entry_params(update_type: "Typed by the user")

      expect(response.status).to eq(200)
      expect(response.parsed_body["update"]["update_type"]).to eq(
        "Typed by the user"
      )
    end

    it "requires a body or attachments" do
      post "/atcp/cases/#{atcp_case.id}/updates.json",
           params: entry_params(body: nil)

      expect(response.status).to eq(422)
      expect(response.parsed_body["errors"]["body"]).to include(
        I18n.t("atcp_case.errors.update_body_required")
      )
    end

    it "rejects the Closed status" do
      post "/atcp/cases/#{atcp_case.id}/updates.json",
           params: entry_params(status: "Closed")

      expect(response.status).to eq(422)
      expect(response.parsed_body["errors"]["status"]).to include(
        I18n.t("atcp_case.errors.status_invalid")
      )
    end

    it "rejects unknown attachment ids" do
      post "/atcp/cases/#{atcp_case.id}/updates.json",
           params: entry_params(body: nil, upload_ids: [999_999])

      expect(response.status).to eq(422)
      expect(response.parsed_body["errors"]["upload_ids"]).to include(
        I18n.t("atcp_case.errors.attachment_not_found", filename: "999999")
      )
      expect(AtcpCaseUpdate.where(case_id: atcp_case.id).count).to eq(0)
    end

    it "rejects attachments owned by other users" do
      upload = pdf_upload(other_internal_user)

      post "/atcp/cases/#{atcp_case.id}/updates.json",
           params: entry_params(body: nil, upload_ids: [upload.id])

      expect(response.status).to eq(422)
      expect(response.parsed_body["errors"]["upload_ids"]).to include(
        I18n.t(
          "atcp_case.errors.attachment_not_owned",
          filename: "evidence.pdf"
        )
      )
      expect(AtcpCaseUpdate.where(case_id: atcp_case.id).count).to eq(0)
    end

    it "rejects attachments that are already used" do
      upload = pdf_upload
      existing =
        Fabricate(:atcp_case_update, atcp_case: atcp_case, user: internal_user)
      AtcpCaseAttachment.create!(
        case_id: atcp_case.id,
        update_id: existing.id,
        upload_id: upload.id
      )

      post "/atcp/cases/#{atcp_case.id}/updates.json",
           params: entry_params(body: nil, upload_ids: [upload.id])

      expect(response.status).to eq(422)
      expect(response.parsed_body["errors"]["upload_ids"]).to include(
        I18n.t(
          "atcp_case.errors.attachment_already_used",
          filename: "evidence.pdf"
        )
      )
    end

    it "rejects disallowed extensions" do
      upload = Fabricate(:upload, user: internal_user)
      upload.update_columns(original_filename: "script.exe", extension: "exe")

      post "/atcp/cases/#{atcp_case.id}/updates.json",
           params: entry_params(body: nil, upload_ids: [upload.id])

      expect(response.status).to eq(422)
      expect(response.parsed_body["errors"]["upload_ids"]).to include(
        I18n.t(
          "atcp_case.errors.attachment_extension_not_allowed",
          filename: "script.exe"
        )
      )
    end

    it "rejects oversized attachments" do
      SiteSetting.atcp_case_max_attachment_mb = 1
      upload = pdf_upload(internal_user, filesize: 2.megabytes)

      post "/atcp/cases/#{atcp_case.id}/updates.json",
           params: entry_params(body: nil, upload_ids: [upload.id])

      expect(response.status).to eq(422)
      expect(response.parsed_body["errors"]["upload_ids"]).to include(
        I18n.t(
          "atcp_case.errors.attachment_too_large",
          filename: "evidence.pdf",
          max_mb: 1
        )
      )
    end

    it "accepts an allowed extension case-insensitively" do
      upload = pdf_upload(internal_user, extension: "PDF")

      post "/atcp/cases/#{atcp_case.id}/updates.json",
           params: entry_params(body: nil, upload_ids: [upload.id])

      expect(response.status).to eq(200)
      expect(response.parsed_body["update"]["attachments"].size).to eq(1)
    end

    it "limits the number of attachments" do
      uploads = Array.new(21) { pdf_upload }

      post "/atcp/cases/#{atcp_case.id}/updates.json",
           params: entry_params(body: nil, upload_ids: uploads.map(&:id))

      expect(response.status).to eq(422)
      expect(response.parsed_body["errors"]["upload_ids"]).to include(
        I18n.t("atcp_case.errors.too_many_attachments", max: 20)
      )
      expect(AtcpCaseUpdate.where(case_id: atcp_case.id).count).to eq(0)
    end

    it "returns 404 for a missing case" do
      post "/atcp/cases/0/updates.json", params: entry_params

      expect(response.status).to eq(404)
    end
  end

  describe "#update" do
    before { sign_in(internal_user) }

    it "edits a user entry and records the edit history" do
      entry =
        Fabricate(
          :atcp_case_update,
          atcp_case: atcp_case,
          user: internal_user,
          update_type: "General note",
          body: "First note"
        )

      put "/atcp/cases/#{atcp_case.id}/updates/#{entry.id}.json",
          params: {
            body: "Revised note",
            update_type: "Vendor communication"
          }

      expect(response.status).to eq(200)
      body = response.parsed_body["update"]
      expect(body["body"]).to eq("Revised note")
      expect(body["update_type"]).to eq("Vendor communication")
      expect(body["edited_at"]).to be_present

      entry.reload
      expect(entry.body).to eq("Revised note")
      expect(entry.update_type).to eq("Vendor communication")
      expect(entry.edited_at).to be_present

      history = entry.details["edit_history"]
      expect(history.size).to eq(1)
      expect(history.first["previous_body"]).to eq("First note")
      expect(history.first["previous_update_type"]).to eq("General note")
      expect(history.first["edited_by_id"]).to eq(internal_user.id)
      expect(history.first["edited_at"]).to be_present
    end

    it "appends to the existing edit history" do
      entry =
        Fabricate(
          :atcp_case_update,
          atcp_case: atcp_case,
          user: internal_user,
          body: "v1"
        )

      put "/atcp/cases/#{atcp_case.id}/updates/#{entry.id}.json",
          params: {
            body: "v2"
          }
      put "/atcp/cases/#{atcp_case.id}/updates/#{entry.id}.json",
          params: {
            body: "v3"
          }

      history = entry.reload.details["edit_history"]
      expect(history.size).to eq(2)
      expect(history.map { |edit| edit["previous_body"] }).to eq(%w[v1 v2])
    end

    it "rejects clearing the body when the entry has no attachment" do
      entry =
        Fabricate(
          :atcp_case_update,
          atcp_case: atcp_case,
          user: internal_user,
          body: "Some note",
          update_type: "General note"
        )

      put "/atcp/cases/#{atcp_case.id}/updates/#{entry.id}.json",
          params: {
            body: "",
            update_type: "Testing"
          }

      expect(response.status).to eq(422)
      expect(response.parsed_body["errors"]["body"]).to include(
        I18n.t("atcp_case.errors.update_body_required")
      )
      entry.reload
      expect(entry.body).to eq("Some note")
      expect(entry.update_type).to eq("General note")
      expect(entry.edited_at).to be_nil
      expect(entry.details["edit_history"]).to be_nil
    end

    it "allows clearing the body when the entry has an attachment" do
      entry =
        Fabricate(
          :atcp_case_update,
          atcp_case: atcp_case,
          user: internal_user,
          body: "Some note"
        )
      upload = pdf_upload
      AtcpCaseAttachment.create!(
        case_id: atcp_case.id,
        update_id: entry.id,
        upload_id: upload.id
      )

      put "/atcp/cases/#{atcp_case.id}/updates/#{entry.id}.json",
          params: {
            body: "",
            update_type: "Testing"
          }

      expect(response.status).to eq(200)
      body = response.parsed_body["update"]
      expect(body["body"]).to be_nil
      expect(body["update_type"]).to eq("Testing")
      entry.reload
      expect(entry.edited_at).to be_present
      expect(entry.details["edit_history"].size).to eq(1)
    end

    it "adds an attachment during an attachment-only edit" do
      entry =
        Fabricate(
          :atcp_case_update,
          atcp_case: atcp_case,
          user: internal_user,
          update_type: "General note",
          body: "Original note"
        )
      upload = pdf_upload

      put "/atcp/cases/#{atcp_case.id}/updates/#{entry.id}.json",
          params: {
            upload_ids: [upload.id]
          }

      expect(response.status).to eq(200)
      update_json = response.parsed_body["update"]
      expect(update_json["body"]).to eq("Original note")
      expect(update_json["attachments"].map { |row| row["upload_id"] }).to eq(
        [upload.id]
      )

      entry.reload
      expect(entry.edited_at).to be_present
      history = entry.details["edit_history"]
      expect(history.size).to eq(1)
      expect(history.first["added_attachments"]).to eq(
        [{ "upload_id" => upload.id, "filename" => "evidence.pdf" }]
      )
      expect(history.first).not_to have_key("removed_attachments")
    end

    it "soft deletes a removed attachment without deleting its upload" do
      entry =
        Fabricate(
          :atcp_case_update,
          atcp_case: atcp_case,
          user: internal_user,
          body: "Keep this note"
        )
      upload = pdf_upload
      attachment = attach_upload(entry, upload)

      put "/atcp/cases/#{atcp_case.id}/updates/#{entry.id}.json",
          params: {
            remove_attachment_ids: [attachment.id]
          }

      expect(response.status).to eq(200)
      expect(response.parsed_body["update"]["attachments"]).to eq([])

      attachment = AtcpCaseAttachment.with_deleted.find(attachment.id)
      expect(attachment.deleted_at).to be_present
      expect(attachment.deleted_by_id).to eq(internal_user.id)
      expect(Upload.exists?(upload.id)).to eq(true)
      expect(UploadReference.exists?(upload_id: upload.id)).to eq(true)

      entry.reload
      expect(entry.edited_at).to be_present
      history = entry.details["edit_history"]
      expect(history.first["removed_attachments"]).to eq(
        [{ "upload_id" => upload.id, "filename" => "evidence.pdf" }]
      )
      expect(history.first).not_to have_key("added_attachments")

      get "/atcp/cases/#{atcp_case.id}.json"
      update_json =
        response.parsed_body["case"]["updates"].find do |row|
          row["id"] == entry.id
        end
      expect(update_json["attachments"]).to eq([])
    end

    it "adds and removes attachments in the same edit" do
      entry =
        Fabricate(
          :atcp_case_update,
          atcp_case: atcp_case,
          user: internal_user,
          body: "Replace the evidence"
        )
      old_upload = pdf_upload
      old_attachment = attach_upload(entry, old_upload)
      new_upload = pdf_upload

      put "/atcp/cases/#{atcp_case.id}/updates/#{entry.id}.json",
          params: {
            upload_ids: [new_upload.id],
            remove_attachment_ids: [old_attachment.id]
          }

      expect(response.status).to eq(200)
      expect(
        response.parsed_body["update"]["attachments"].map do |row|
          row["upload_id"]
        end
      ).to eq([new_upload.id])

      expect(
        AtcpCaseAttachment.with_deleted.find(old_attachment.id).deleted_at
      ).to be_present
      history = entry.reload.details["edit_history"].first
      expect(history["added_attachments"]).to eq(
        [{ "upload_id" => new_upload.id, "filename" => "evidence.pdf" }]
      )
      expect(history["removed_attachments"]).to eq(
        [{ "upload_id" => old_upload.id, "filename" => "evidence.pdf" }]
      )
    end

    it "logs the edit in the staff action log" do
      entry =
        Fabricate(
          :atcp_case_update,
          atcp_case: atcp_case,
          user: internal_user,
          body: "Keep this note"
        )
      upload = pdf_upload
      attachment = attach_upload(entry, upload)

      expect {
        put "/atcp/cases/#{atcp_case.id}/updates/#{entry.id}.json",
            params: {
              remove_attachment_ids: [attachment.id]
            }
      }.to change {
        UserHistory.where(custom_type: "atcp_case_update_edited").count
      }.by(1)

      log = UserHistory.where(custom_type: "atcp_case_update_edited").last
      expect(log.acting_user_id).to eq(internal_user.id)
      expect(log.details).to include(
        "case_id: #{atcp_case.id}",
        "update_id: #{entry.id}",
        "system_event: ",
        "added_upload_ids: []",
        "removed_upload_ids: [#{upload.id}]",
        "edited_by_author: true"
      )
    end

    it "does not log an author edit when no attachment is removed" do
      entry =
        Fabricate(
          :atcp_case_update,
          atcp_case: atcp_case,
          user: internal_user,
          body: "Keep this note"
        )

      expect {
        put "/atcp/cases/#{atcp_case.id}/updates/#{entry.id}.json",
            params: {
              body: "Revised note"
            }
      }.not_to change {
        UserHistory.where(custom_type: "atcp_case_update_edited").count
      }

      expect(response.status).to eq(200)
    end

    it "allows an admin to edit another user's entry and logs the edit" do
      entry =
        Fabricate(
          :atcp_case_update,
          atcp_case: atcp_case,
          user: internal_user,
          body: "Original note"
        )
      sign_in(admin_user)

      expect {
        put "/atcp/cases/#{atcp_case.id}/updates/#{entry.id}.json",
            params: {
              body: "Admin edit"
            }
      }.to change {
        UserHistory.where(custom_type: "atcp_case_update_edited").count
      }.by(1)

      expect(response.status).to eq(200)
      expect(entry.reload.body).to eq("Admin edit")

      log = UserHistory.where(custom_type: "atcp_case_update_edited").last
      expect(log.details).to include(
        "system_event: ",
        "edited_by_author: false"
      )
    end

    it "rejects removing an attachment from another update" do
      entry =
        Fabricate(:atcp_case_update, atcp_case: atcp_case, user: internal_user)
      other_entry =
        Fabricate(:atcp_case_update, atcp_case: atcp_case, user: internal_user)
      upload = pdf_upload
      other_attachment = attach_upload(other_entry, upload)

      put "/atcp/cases/#{atcp_case.id}/updates/#{entry.id}.json",
          params: {
            remove_attachment_ids: [other_attachment.id]
          }

      expect(response.status).to eq(422)
      expect(
        response.parsed_body["errors"]["remove_attachment_ids"]
      ).to include(
        I18n.t(
          "atcp_case.errors.attachment_not_in_update",
          ids: other_attachment.id
        )
      )
      expect(AtcpCaseAttachment.exists?(other_attachment.id)).to eq(true)
      expect(entry.reload.edited_at).to be_nil
      expect(entry.details["edit_history"]).to be_nil
    end

    it "rejects edits that exceed the attachment limit" do
      entry =
        Fabricate(
          :atcp_case_update,
          atcp_case: atcp_case,
          user: internal_user,
          body: "Full of evidence"
        )
      Array.new(20) do
        upload = pdf_upload
        attach_upload(entry, upload)
      end
      upload = pdf_upload

      put "/atcp/cases/#{atcp_case.id}/updates/#{entry.id}.json",
          params: {
            upload_ids: [upload.id]
          }

      expect(response.status).to eq(422)
      expect(response.parsed_body["errors"]["upload_ids"]).to include(
        I18n.t("atcp_case.errors.too_many_attachments", max: 20)
      )
      expect(
        AtcpCaseAttachment.exists?(update_id: entry.id, upload_id: upload.id)
      ).to eq(false)
      expect(entry.reload.edited_at).to be_nil
    end

    it "rejects a new attachment owned by another user" do
      entry =
        Fabricate(:atcp_case_update, atcp_case: atcp_case, user: internal_user)
      upload = pdf_upload(other_internal_user)

      put "/atcp/cases/#{atcp_case.id}/updates/#{entry.id}.json",
          params: {
            upload_ids: [upload.id]
          }

      expect(response.status).to eq(422)
      expect(response.parsed_body["errors"]["upload_ids"]).to include(
        I18n.t(
          "atcp_case.errors.attachment_not_owned",
          filename: "evidence.pdf"
        )
      )
      expect(
        AtcpCaseAttachment.exists?(update_id: entry.id, upload_id: upload.id)
      ).to eq(false)
    end

    it "rejects an upload used by a soft-deleted attachment" do
      entry =
        Fabricate(:atcp_case_update, atcp_case: atcp_case, user: internal_user)
      upload = pdf_upload
      attachment = attach_upload(entry, upload)
      attachment.soft_delete!(internal_user)

      put "/atcp/cases/#{atcp_case.id}/updates/#{entry.id}.json",
          params: {
            upload_ids: [upload.id]
          }

      expect(response.status).to eq(422)
      expect(response.parsed_body["errors"]["upload_ids"]).to include(
        I18n.t(
          "atcp_case.errors.attachment_already_used",
          filename: "evidence.pdf"
        )
      )
    end

    it "rejects removing the last attachment when there is no note" do
      entry =
        Fabricate(
          :atcp_case_update,
          atcp_case: atcp_case,
          user: internal_user,
          body: nil
        )
      upload = pdf_upload
      attachment = attach_upload(entry, upload)

      put "/atcp/cases/#{atcp_case.id}/updates/#{entry.id}.json",
          params: {
            remove_attachment_ids: [attachment.id]
          }

      expect(response.status).to eq(422)
      expect(response.parsed_body["errors"]["body"]).to include(
        I18n.t("atcp_case.errors.update_body_required")
      )
      expect(AtcpCaseAttachment.exists?(attachment.id)).to eq(true)
      expect(entry.reload.edited_at).to be_nil
      expect(entry.details["edit_history"]).to be_nil
    end

    it "rejects an edit with no effective changes" do
      entry =
        Fabricate(
          :atcp_case_update,
          atcp_case: atcp_case,
          user: internal_user,
          body: "Original note"
        )

      put "/atcp/cases/#{atcp_case.id}/updates/#{entry.id}.json",
          params: {
            upload_ids: [],
            remove_attachment_ids: []
          }

      expect(response.status).to eq(422)
      expect(response.parsed_body["errors"]["base"]).to include(
        I18n.t("atcp_case.errors.update_edit_required")
      )
      expect(entry.reload.edited_at).to be_nil
    end

    it "allows the author to edit a system entry body without changing structured fields" do
      entry =
        system_entry(
          body: "Original context",
          details: {
            "context" => "original"
          }
        )

      expect {
        put "/atcp/cases/#{atcp_case.id}/updates/#{entry.id}.json",
            params: {
              body: "Updated context"
            }
      }.not_to change {
        UserHistory.where(custom_type: "atcp_case_update_edited").count
      }

      expect(response.status).to eq(200)
      entry.reload
      expect(entry.body).to eq("Updated context")
      expect(entry.edited_at).to be_present
      expect(entry.system_event).to eq("status_changed")
      expect(entry.from_value).to eq("Open")
      expect(entry.to_value).to eq("In Progress")
      expect(entry.details["context"]).to eq("original")

      history = entry.details["edit_history"]
      expect(history.size).to eq(1)
      expect(history.first).to include(
        "previous_body" => "Original context",
        "edited_by_id" => internal_user.id
      )
      expect(history.first["edited_at"]).to be_present
    end

    it "allows an admin to edit another user's system entry and logs it" do
      entry = system_entry(body: "Original context")
      sign_in(admin_user)

      expect {
        put "/atcp/cases/#{atcp_case.id}/updates/#{entry.id}.json",
            params: {
              body: "Admin context"
            }
      }.to change {
        UserHistory.where(custom_type: "atcp_case_update_edited").count
      }.by(1)

      expect(response.status).to eq(200)
      expect(entry.reload.body).to eq("Admin context")

      log = UserHistory.where(custom_type: "atcp_case_update_edited").last
      expect(log.acting_user_id).to eq(admin_user.id)
      expect(log.details).to include(
        "case_id: #{atcp_case.id}",
        "update_id: #{entry.id}",
        "system_event: status_changed",
        "added_upload_ids: []",
        "removed_upload_ids: []",
        "edited_by_author: false"
      )
    end

    it "forbids another internal member from editing a system entry" do
      entry = system_entry(body: "Original context")
      sign_in(other_internal_user)

      put "/atcp/cases/#{atcp_case.id}/updates/#{entry.id}.json",
          params: {
            body: "Nope"
          }

      expect(response.status).to eq(403)
      expect(entry.reload.body).to eq("Original context")
    end

    it "rejects structured fields when editing a system entry" do
      entry = system_entry(body: "Original context")

      [
        { body: "Nope", update_type: "General note" },
        { body: "Nope", upload_ids: [1] },
        { body: "Nope", remove_attachment_ids: [1] }
      ].each do |params|
        put "/atcp/cases/#{atcp_case.id}/updates/#{entry.id}.json",
            params: params

        expect(response.status).to eq(422)
        expect(response.parsed_body["errors"]["base"]).to include(
          I18n.t("atcp_case.errors.system_update_body_only")
        )
      end

      expect(entry.reload.body).to eq("Original context")
      expect(entry.edited_at).to be_nil
    end

    it "allows clearing the body of a non-reopened system entry" do
      entry = system_entry(body: "Remove this context")

      put "/atcp/cases/#{atcp_case.id}/updates/#{entry.id}.json",
          params: {
            body: ""
          }

      expect(response.status).to eq(200)
      expect(entry.reload.body).to be_nil
      expect(entry.edited_at).to be_present
    end

    it "rejects clearing the body of a reopened system entry" do
      entry =
        system_entry(system_event: "reopened", body: "Original reopen reason")

      put "/atcp/cases/#{atcp_case.id}/updates/#{entry.id}.json",
          params: {
            body: " "
          }

      expect(response.status).to eq(422)
      expect(response.parsed_body["errors"]["body"]).to include(
        I18n.t("atcp_case.errors.update_body_required")
      )
      expect(entry.reload.body).to eq("Original reopen reason")
      expect(entry.edited_at).to be_nil
    end

    it "rejects a system entry edit with the same body" do
      entry = system_entry(body: "Same context")

      put "/atcp/cases/#{atcp_case.id}/updates/#{entry.id}.json",
          params: {
            body: "Same context"
          }

      expect(response.status).to eq(422)
      expect(response.parsed_body["errors"]["base"]).to include(
        I18n.t("atcp_case.errors.update_edit_required")
      )
      expect(entry.reload.edited_at).to be_nil
    end

    it "normalizes surrounding whitespace before comparing the body" do
      entry = system_entry(body: "Same context")

      put "/atcp/cases/#{atcp_case.id}/updates/#{entry.id}.json",
          params: {
            body: "  Same context  "
          }

      expect(response.status).to eq(422)
      expect(response.parsed_body["errors"]["base"]).to include(
        I18n.t("atcp_case.errors.update_edit_required")
      )
      expect(entry.reload.body).to eq("Same context")
      expect(entry.edited_at).to be_nil
      expect(entry.details["edit_history"]).to be_nil
    end

    it "treats blank stored and submitted bodies as unchanged" do
      entry = system_entry(body: "")

      put "/atcp/cases/#{atcp_case.id}/updates/#{entry.id}.json",
          params: {
            body: " "
          }

      expect(response.status).to eq(422)
      expect(response.parsed_body["errors"]["base"]).to include(
        I18n.t("atcp_case.errors.update_edit_required")
      )
      expect(entry.reload.body).to eq("")
      expect(entry.edited_at).to be_nil
      expect(entry.details["edit_history"]).to be_nil
    end

    it "rejects editing entries of a closed case for authors and admins" do
      entry =
        Fabricate(:atcp_case_update, atcp_case: atcp_case, user: internal_user)
      original_body = entry.body
      atcp_case.update!(
        status: "Closed",
        close_reason: "Duplicate",
        closed_at: 1.hour.ago
      )

      [internal_user, admin_user].each do |user|
        sign_in(user)
        put "/atcp/cases/#{atcp_case.id}/updates/#{entry.id}.json",
            params: {
              body: "Nope"
            }

        expect(response.status).to eq(422)
        expect(response.parsed_body["errors"]["base"]).to include(
          I18n.t("atcp_case.errors.case_closed")
        )
      end

      expect(entry.reload.body).to eq(original_body)
      expect(entry.edited_at).to be_nil
    end

    it "re-checks the closed status inside the lock" do
      entry =
        Fabricate(
          :atcp_case_update,
          atcp_case: atcp_case,
          user: internal_user,
          body: "Original"
        )
      stale = AtcpCase.find(atcp_case.id)
      atcp_case.update_columns(
        status: "Closed",
        close_reason: "Duplicate",
        closed_at: 1.hour.ago
      )
      allow_any_instance_of(Atcp::CaseUpdatesController).to receive(
        :find_case!
      ).and_return(stale)

      put "/atcp/cases/#{atcp_case.id}/updates/#{entry.id}.json",
          params: {
            body: "Nope"
          }

      expect(response.status).to eq(422)
      expect(response.parsed_body["errors"]["base"]).to include(
        I18n.t("atcp_case.errors.case_closed")
      )
      entry.reload
      expect(entry.body).to eq("Original")
      expect(entry.edited_at).to be_nil
    end

    it "requires something to edit" do
      entry =
        Fabricate(:atcp_case_update, atcp_case: atcp_case, user: internal_user)

      put "/atcp/cases/#{atcp_case.id}/updates/#{entry.id}.json", params: {}

      expect(response.status).to eq(422)
      expect(response.parsed_body["errors"]["base"]).to include(
        I18n.t("atcp_case.errors.update_edit_required")
      )
    end

    it "accepts an arbitrary update type" do
      entry =
        Fabricate(:atcp_case_update, atcp_case: atcp_case, user: internal_user)

      put "/atcp/cases/#{atcp_case.id}/updates/#{entry.id}.json",
          params: {
            update_type: "  Typed during edit  "
          }

      expect(response.status).to eq(200)
      expect(response.parsed_body["update"]["update_type"]).to eq(
        "Typed during edit"
      )
    end

    it "requires a non-blank update type when one is sent" do
      entry =
        Fabricate(:atcp_case_update, atcp_case: atcp_case, user: internal_user)

      put "/atcp/cases/#{atcp_case.id}/updates/#{entry.id}.json",
          params: {
            update_type: "   "
          }

      expect(response.status).to eq(422)
      expect(response.parsed_body["errors"]["update_type"]).to include(
        I18n.t("atcp_case.errors.update_type_required")
      )
    end

    it "rejects an update type longer than 100 characters" do
      entry =
        Fabricate(:atcp_case_update, atcp_case: atcp_case, user: internal_user)

      put "/atcp/cases/#{atcp_case.id}/updates/#{entry.id}.json",
          params: {
            update_type: "x" * 101
          }

      expect(response.status).to eq(422)
      expect(response.parsed_body["errors"]["update_type"]).to include(
        I18n.t("atcp_case.errors.update_type_too_long")
      )
    end

    it "returns 404 for an entry from another case" do
      other_case = Fabricate(:atcp_case, created_by: internal_user)
      entry =
        Fabricate(:atcp_case_update, atcp_case: other_case, user: internal_user)

      put "/atcp/cases/#{atcp_case.id}/updates/#{entry.id}.json",
          params: {
            body: "Nope"
          }

      expect(response.status).to eq(404)
    end

    it "returns 404 for a missing entry" do
      put "/atcp/cases/#{atcp_case.id}/updates/0.json", params: { body: "Nope" }

      expect(response.status).to eq(404)
    end
  end

  describe "#destroy" do
    before { sign_in(admin_user) }

    it "soft deletes an update and hides it from the case" do
      entry =
        Fabricate(
          :atcp_case_update,
          atcp_case: atcp_case,
          user: internal_user,
          body: "Remove me"
        )

      delete "/atcp/cases/#{atcp_case.id}/updates/#{entry.id}.json"

      expect(response.status).to eq(204)

      get "/atcp/cases/#{atcp_case.id}.json"
      update_ids =
        response.parsed_body["case"]["updates"].map { |update| update["id"] }
      expect(update_ids).not_to include(entry.id)

      expect(
        AtcpCaseUpdate.with_deleted.find(entry.id).deleted_at
      ).to be_present
    end

    it "soft deletes system entries without changing the case" do
      atcp_case.update!(
        status: "On Hold",
        closed_at: 1.hour.ago,
        severity: "High",
        assignee: other_internal_user
      )

      [internal_user, admin_user].each do |actor|
        entry = system_entry(body: "System context")
        sign_in(actor)

        expect {
          delete "/atcp/cases/#{atcp_case.id}/updates/#{entry.id}.json"
        }.to change {
          UserHistory.where(custom_type: "atcp_case_update_deleted").count
        }.by(1)

        expect(response.status).to eq(204)
        deleted_entry = AtcpCaseUpdate.with_deleted.find(entry.id)
        expect(deleted_entry.deleted_at).to be_present
        expect(deleted_entry.deleted_by_id).to eq(actor.id)

        log = UserHistory.where(custom_type: "atcp_case_update_deleted").last
        expect(log.details).to include(
          "case_id: #{atcp_case.id}",
          "update_id: #{entry.id}",
          "system_event: status_changed"
        )

        atcp_case.reload
        expect(atcp_case.status).to eq("On Hold")
        expect(atcp_case.closed_at).to be_present
        expect(atcp_case.severity).to eq("High")
        expect(atcp_case.assignee_id).to eq(other_internal_user.id)
      end
    end

    it "rejects deleting entries of a closed case for authors and admins" do
      entry =
        Fabricate(:atcp_case_update, atcp_case: atcp_case, user: internal_user)
      atcp_case.update!(
        status: "Closed",
        close_reason: "Duplicate",
        closed_at: 1.hour.ago
      )

      [internal_user, admin_user].each do |user|
        sign_in(user)
        delete "/atcp/cases/#{atcp_case.id}/updates/#{entry.id}.json"

        expect(response.status).to eq(422)
        expect(response.parsed_body["errors"]["base"]).to include(
          I18n.t("atcp_case.errors.case_closed")
        )
      end

      expect(AtcpCaseUpdate.with_deleted.find(entry.id).deleted_at).to be_nil
    end

    it "returns 404 for a missing entry" do
      delete "/atcp/cases/#{atcp_case.id}/updates/0.json"

      expect(response.status).to eq(404)
    end
  end
end
