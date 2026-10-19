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

    it "allows internal members to create and edit but not delete updates" do
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

    it "requires a valid update type" do
      post "/atcp/cases/#{atcp_case.id}/updates.json",
           params: entry_params(update_type: nil)

      expect(response.status).to eq(422)
      expect(response.parsed_body["errors"]["update_type"]).to include(
        I18n.t("atcp_case.errors.update_type_required")
      )

      post "/atcp/cases/#{atcp_case.id}/updates.json",
           params: entry_params(update_type: "Made up")

      expect(response.status).to eq(422)
      expect(response.parsed_body["errors"]["update_type"]).to include(
        I18n.t("atcp_case.errors.update_type_invalid")
      )
      expect(AtcpCaseUpdate.where(case_id: atcp_case.id).count).to eq(0)
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

    it "rejects editing system entries" do
      entry =
        Fabricate(
          :atcp_case_update,
          atcp_case: atcp_case,
          user: internal_user,
          is_system: true,
          update_type: nil,
          system_event: "status_changed",
          from_value: "Open",
          to_value: "In Progress"
        )

      put "/atcp/cases/#{atcp_case.id}/updates/#{entry.id}.json",
          params: {
            body: "Nope"
          }

      expect(response.status).to eq(422)
      expect(response.parsed_body["errors"]["base"]).to include(
        I18n.t("atcp_case.errors.system_update_immutable")
      )
    end

    it "rejects editing entries of a closed case" do
      entry =
        Fabricate(:atcp_case_update, atcp_case: atcp_case, user: internal_user)
      atcp_case.update!(
        status: "Closed",
        close_reason: "Duplicate",
        closed_at: 1.hour.ago
      )

      put "/atcp/cases/#{atcp_case.id}/updates/#{entry.id}.json",
          params: {
            body: "Nope"
          }

      expect(response.status).to eq(422)
      expect(response.parsed_body["errors"]["base"]).to include(
        I18n.t("atcp_case.errors.case_closed")
      )
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

    it "validates a sent update type" do
      entry =
        Fabricate(:atcp_case_update, atcp_case: atcp_case, user: internal_user)

      put "/atcp/cases/#{atcp_case.id}/updates/#{entry.id}.json",
          params: {
            update_type: "Bogus"
          }

      expect(response.status).to eq(422)
      expect(response.parsed_body["errors"]["update_type"]).to include(
        I18n.t("atcp_case.errors.update_type_invalid")
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

    it "rejects deleting system entries" do
      entry =
        Fabricate(
          :atcp_case_update,
          atcp_case: atcp_case,
          user: internal_user,
          is_system: true,
          update_type: nil,
          system_event: "status_changed",
          from_value: "Open",
          to_value: "In Progress"
        )

      delete "/atcp/cases/#{atcp_case.id}/updates/#{entry.id}.json"

      expect(response.status).to eq(422)
      expect(response.parsed_body["errors"]["base"]).to include(
        I18n.t("atcp_case.errors.system_update_immutable")
      )
      expect(entry.reload.deleted_at).to be_nil
    end

    it "returns 404 for a missing entry" do
      delete "/atcp/cases/#{atcp_case.id}/updates/0.json"

      expect(response.status).to eq(404)
    end
  end
end
