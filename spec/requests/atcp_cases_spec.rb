# frozen_string_literal: true

RSpec.describe "Atcp cases" do
  fab!(:internal_group, :group)
  fab!(:internal_user, :user)
  fab!(:other_internal_user, :user)
  fab!(:outsider, :user)
  fab!(:moderator)
  fab!(:admin_user, :admin)
  fab!(:product, :atcp_product)
  fab!(:second_product, :atcp_product)

  before do
    enable_current_plugin
    internal_group.add(internal_user)
    internal_group.add(other_internal_user)
    SiteSetting.atcp_internal_groups = internal_group.id.to_s
  end

  def endpoint_statuses(case_id:, params: {})
    statuses = []

    get "/atcp/cases.json"
    statuses << response.status
    get "/atcp/cases/form_options.json"
    statuses << response.status
    get "/atcp/cases/pic_candidates.json"
    statuses << response.status
    get "/atcp/cases/#{case_id}.json"
    statuses << response.status
    post "/atcp/cases.json", params: params
    statuses << response.status

    statuses
  end

  def list_ids
    response.parsed_body["cases"].map { |item| item["id"] }
  end

  def create_open_case!(attrs = {})
    Fabricate(:atcp_case, { created_by: internal_user }.merge(attrs))
  end

  describe "access guard" do
    it "blocks anonymous users on every endpoint" do
      atcp_case = create_open_case!

      expect(endpoint_statuses(case_id: atcp_case.id)).to eq(
        [403, 403, 403, 403, 403]
      )
    end

    it "blocks signed in non-internal users on every endpoint" do
      sign_in(outsider)
      atcp_case = create_open_case!

      expect(endpoint_statuses(case_id: atcp_case.id)).to eq(
        [403, 403, 403, 403, 403]
      )
    end

    it "blocks moderators that are not internal members" do
      sign_in(moderator)
      atcp_case = create_open_case!

      expect(endpoint_statuses(case_id: atcp_case.id)).to eq(
        [403, 403, 403, 403, 403]
      )
    end

    it "allows internal non-staff members on every endpoint" do
      sign_in(internal_user)
      atcp_case = create_open_case!

      expect(endpoint_statuses(case_id: atcp_case.id)).to eq(
        [200, 200, 200, 200, 422]
      )
    end

    it "allows admins on every endpoint" do
      sign_in(admin_user)
      atcp_case = create_open_case!

      expect(endpoint_statuses(case_id: atcp_case.id)).to eq(
        [200, 200, 200, 200, 422]
      )
    end

    it "blocks the lifecycle endpoints for anonymous and non-internal users" do
      atcp_case = create_open_case!

      [nil, outsider, moderator].each do |user|
        sign_in(user) if user

        put "/atcp/cases/#{atcp_case.id}.json", params: { title: "Nope" }
        expect(response.status).to eq(403)

        post "/atcp/cases/#{atcp_case.id}/close.json",
             params: {
               close_reason: "Duplicate"
             }
        expect(response.status).to eq(403)

        post "/atcp/cases/#{atcp_case.id}/reopen.json",
             params: {
               reason: "Reopen"
             }
        expect(response.status).to eq(403)

        post "/atcp/cases/#{atcp_case.id}/updates.json",
             params: {
               update_type: "General note",
               body: "Hi"
             }
        expect(response.status).to eq(403)

        delete "/atcp/cases/#{atcp_case.id}/updates/1.json"
        expect(response.status).to eq(403)
      end
    end

    it "allows internal members and admins through the case lifecycle" do
      [internal_user, admin_user].each do |user|
        sign_in(user)
        atcp_case = create_open_case!

        put "/atcp/cases/#{atcp_case.id}.json", params: { title: "Renamed" }
        expect(response.status).to eq(200)

        post "/atcp/cases/#{atcp_case.id}/updates.json",
             params: {
               update_type: "General note",
               body: "Looking into it"
             }
        expect(response.status).to eq(200)

        post "/atcp/cases/#{atcp_case.id}/close.json",
             params: {
               close_reason: "Duplicate"
             }
        expect(response.status).to eq(200)

        post "/atcp/cases/#{atcp_case.id}/reopen.json",
             params: {
               reason: "Customer replied"
             }
        expect(response.status).to eq(200)
      end
    end
  end

  describe "#index" do
    before { sign_in(internal_user) }

    it "returns only active cases by default with pagination metadata" do
      25.times { |index| create_open_case!(opened_at: index.minutes.ago) }
      3.times do
        create_open_case!(
          status: "Closed",
          close_reason: "Duplicate",
          closed_at: 1.hour.ago
        )
      end

      get "/atcp/cases.json"

      body = response.parsed_body
      expect(response.status).to eq(200)
      expect(body["cases"].size).to eq(20)
      expect(body["cases"].map { |item| item["status"] }).to all(eq("Open"))
      expect(body["total_count"]).to eq(25)
      expect(body["page"]).to eq(1)
      expect(body["per_page"]).to eq(20)
      expect(body["total_pages"]).to eq(2)
      expect(body["status_counts"]).to include("active" => 25, "Closed" => 3)
    end

    it "clamps page and per_page" do
      3.times { |index| create_open_case!(opened_at: index.minutes.ago) }

      get "/atcp/cases.json", params: { page: 0, per_page: 999 }
      body = response.parsed_body
      expect(body["page"]).to eq(1)
      expect(body["per_page"]).to eq(100)
      expect(body["cases"].size).to eq(3)

      get "/atcp/cases.json", params: { page: 2, per_page: 2 }
      body = response.parsed_body
      expect(body["page"]).to eq(2)
      expect(body["per_page"]).to eq(2)
      expect(body["cases"].size).to eq(1)
    end

    it "falls back to the default per_page for blank or non-numeric values" do
      3.times { |index| create_open_case!(opened_at: index.minutes.ago) }

      ["", "abc", "0", "-5"].each do |value|
        get "/atcp/cases.json", params: { per_page: value }
        body = response.parsed_body

        expect(response.status).to eq(200)
        expect(body["per_page"]).to eq(20)
      end

      get "/atcp/cases.json", params: { page: "abc" }

      expect(response.parsed_body["page"]).to eq(1)
    end

    it "orders cases by opened_at descending" do
      older = create_open_case!(opened_at: 2.days.ago)
      newer = create_open_case!(opened_at: 1.hour.ago)

      get "/atcp/cases.json"

      expect(list_ids).to eq([newer.id, older.id])
    end

    it "filters by severity, case type, assignee and product" do
      target =
        create_open_case!(
          severity: "Critical",
          case_type: "Performance",
          assignee: other_internal_user
        )
      Fabricate(
        :atcp_case_product,
        atcp_case: target,
        atcp_product: second_product
      )
      Fabricate(:atcp_case_product, atcp_case: target, atcp_product: product)
      create_open_case!(severity: "Low", case_type: "Other", status: "On Hold")

      get "/atcp/cases.json",
          params: {
            severity: "Critical",
            case_type: "Performance",
            assignee_id: other_internal_user.id,
            product_id: second_product.id
          }

      expect(list_ids).to eq([target.id])
    end

    it "ignores malformed text filters without erroring" do
      create_open_case!(severity: "High")

      get "/atcp/cases.json", params: { severity: { "nested" => "value" } }

      expect(response.status).to eq(200)
      expect(response.parsed_body["cases"]).to eq([])
    end

    it "rejects non-numeric product and assignee filters" do
      get "/atcp/cases.json", params: { product_id: "abc" }

      expect(response.status).to eq(422)
      expect(response.parsed_body["errors"]).to include(
        I18n.t("atcp_case.errors.invalid_filter")
      )

      get "/atcp/cases.json", params: { assignee_id: [internal_user.id] }

      expect(response.status).to eq(422)
      expect(response.parsed_body["errors"]).to include(
        I18n.t("atcp_case.errors.invalid_filter")
      )
    end

    it "filters by status" do
      open_case = create_open_case!
      closed_case =
        create_open_case!(
          status: "Closed",
          close_reason: "Duplicate",
          closed_at: 1.hour.ago
        )

      get "/atcp/cases.json", params: { status: "Closed" }

      expect(list_ids).to eq([closed_case.id])
      expect(list_ids).not_to include(open_case.id)
    end

    it "rejects an unknown status filter" do
      get "/atcp/cases.json", params: { status: "Bogus" }

      expect(response.status).to eq(422)
      expect(response.parsed_body["errors"]).to include(
        I18n.t("atcp_case.errors.invalid_status")
      )
    end

    it "searches case number, title and symptom with escaped wildcards" do
      percent = create_open_case!(title: "Disk usage stuck at 100%")
      underscore = create_open_case!(symptom: "Fails on foo_bar test")
      create_open_case!(symptom: "Fails on fooXbar test")

      get "/atcp/cases.json", params: { q: percent.case_number }
      expect(list_ids).to eq([percent.id])

      get "/atcp/cases.json", params: { q: "100%" }
      expect(list_ids).to eq([percent.id])

      get "/atcp/cases.json", params: { q: "foo_bar" }
      expect(list_ids).to eq([underscore.id])
    end

    it "computes status counts with every filter except status" do
      create_open_case!(severity: "High", status: "Open")
      create_open_case!(severity: "High", status: "In Progress")
      create_open_case!(
        severity: "High",
        status: "Closed",
        close_reason: "Duplicate"
      )
      create_open_case!(severity: "Low", status: "Open")

      get "/atcp/cases.json", params: { severity: "High", status: "Open" }

      body = response.parsed_body
      expect(body["cases"].map { |item| item["status"] }).to eq(["Open"])
      expect(body["total_count"]).to eq(1)
      expect(body["status_counts"]).to include(
        "active" => 2,
        "Open" => 1,
        "In Progress" => 1,
        "On Hold" => 0,
        "Solution Found" => 0,
        "Closed" => 1
      )

      get "/atcp/cases.json", params: { severity: "High", status: "Closed" }

      expect(response.parsed_body["status_counts"]["active"]).to eq(2)
    end

    it "filters by opened_at with date ranges" do
      inside =
        create_open_case!(opened_at: Time.zone.parse("2026-03-10 09:00:00"))
      create_open_case!(opened_at: Time.zone.parse("2026-04-01 09:00:00"))

      get "/atcp/cases.json",
          params: {
            date_from: "2026-03-01",
            date_to: "2026-03-31"
          }

      expect(list_ids).to eq([inside.id])
    end

    it "filters dates by the Jakarta calendar day" do
      starts_monday =
        create_open_case!(opened_at: Time.utc(2026, 10, 18, 17, 30))
      create_open_case!(opened_at: Time.utc(2026, 10, 18, 16, 30))

      get "/atcp/cases.json",
          params: {
            date_from: "2026-10-19",
            date_to: "2026-10-19"
          }

      expect(list_ids).to eq([starts_monday.id])
    end

    it "rejects invalid date filters" do
      get "/atcp/cases.json", params: { date_from: "2026-13-01" }

      expect(response.status).to eq(422)
      expect(response.parsed_body["errors"]).to include(
        I18n.t("atcp_case.errors.date_invalid")
      )

      get "/atcp/cases.json",
          params: {
            date_from: "2026-02-01",
            date_to: "2026-01-01"
          }

      expect(response.status).to eq(422)
      expect(response.parsed_body["errors"]).to include(
        I18n.t("atcp_case.errors.date_range_invalid")
      )
    end

    it "returns the expected list item fields" do
      atcp_case =
        create_open_case!(
          assignee: other_internal_user,
          opened_at: 3.days.ago - 1.hour
        )
      Fabricate(:atcp_case_product, atcp_case: atcp_case, atcp_product: product)
      Fabricate(
        :atcp_case_update,
        atcp_case: atcp_case,
        user: other_internal_user,
        update_type: "Waiting for vendor",
        created_at: 1.day.ago
      )

      get "/atcp/cases.json"

      item = response.parsed_body["cases"].first
      expect(item["case_number"]).to eq(atcp_case.case_number)
      expect(item["title"]).to eq(atcp_case.title)
      expect(item["products"]).to eq(
        [
          {
            "id" => product.id,
            "name" => product.name,
            "sku" => product.sku_code
          }
        ]
      )
      expect(item["severity"]).to eq("Medium")
      expect(item["status"]).to eq("Open")
      expect(item["assignee"]).to eq(
        {
          "id" => other_internal_user.id,
          "username" => other_internal_user.username,
          "name" => other_internal_user.name
        }
      )
      expect(item["aging_days"]).to eq(3)
      expect(item["waiting"]["label"]).to eq("Waiting for vendor")
      expect(item["waiting"]["days"]).to eq(1)
    end

    it "does not grow the query count with more cases per page" do
      25.times do |index|
        atcp_case =
          create_open_case!(
            assignee: other_internal_user,
            opened_at: index.minutes.ago
          )
        Fabricate(
          :atcp_case_product,
          atcp_case: atcp_case,
          atcp_product: product
        )
        Fabricate(
          :atcp_case_update,
          atcp_case: atcp_case,
          user: other_internal_user,
          update_type: "Waiting for unit",
          created_at: 2.days.ago
        )
      end

      get "/atcp/cases.json", params: { per_page: 1 }

      queries_for_small_page =
        track_sql_queries { get "/atcp/cases.json", params: { per_page: 5 } }
      queries_for_large_page =
        track_sql_queries { get "/atcp/cases.json", params: { per_page: 25 } }

      expect(queries_for_large_page.size).to eq(queries_for_small_page.size)
    end
  end

  describe "#show" do
    before { sign_in(internal_user) }

    it "sets update permissions in the detail response for the current viewer" do
      atcp_case = create_open_case!
      entry =
        Fabricate(
          :atcp_case_update,
          atcp_case: atcp_case,
          user: internal_user,
          body: "Author note"
        )

      get "/atcp/cases/#{atcp_case.id}.json"
      update =
        response.parsed_body["case"]["updates"].find do |row|
          row["id"] == entry.id
        end
      expect(update["can_edit"]).to eq(true)
      expect(update["can_delete"]).to eq(true)

      sign_in(other_internal_user)
      get "/atcp/cases/#{atcp_case.id}.json"
      update =
        response.parsed_body["case"]["updates"].find do |row|
          row["id"] == entry.id
        end
      expect(update["can_edit"]).to eq(false)
      expect(update["can_delete"]).to eq(false)

      sign_in(admin_user)
      get "/atcp/cases/#{atcp_case.id}.json"
      update =
        response.parsed_body["case"]["updates"].find do |row|
          row["id"] == entry.id
        end
      expect(update["can_edit"]).to eq(true)
      expect(update["can_delete"]).to eq(true)
    end

    it "returns the full case details with updates and attachments" do
      branch = Fabricate(:atcp_branch)
      atcp_case =
        create_open_case!(
          assignee: other_internal_user,
          reporter_branch_id: branch.id,
          reporter_branch_name: "#{branch.name} (#{branch.code})",
          opened_at: 5.days.ago,
          frequency: "Always",
          reproducibility: "Reproducible",
          bios_version: "1.2.3",
          os_driver_info: "Windows 11"
        )
      Fabricate(:atcp_case_product, atcp_case: atcp_case, atcp_product: product)

      system_update =
        Fabricate(
          :atcp_case_update,
          atcp_case: atcp_case,
          user: internal_user,
          is_system: true,
          update_type: nil,
          system_event: "status_changed",
          from_value: "Open",
          to_value: "In Progress",
          created_at: 3.days.ago
        )
      waiting_update =
        Fabricate(
          :atcp_case_update,
          atcp_case: atcp_case,
          user: other_internal_user,
          update_type: "Waiting for unit",
          body: "Unit sent to the lab",
          created_at: 2.days.ago
        )
      upload = Fabricate(:upload, user: other_internal_user)
      AtcpCaseAttachment.create!(
        case_id: atcp_case.id,
        update_id: waiting_update.id,
        upload_id: upload.id
      )

      get "/atcp/cases/#{atcp_case.id}.json"

      expect(response.status).to eq(200)
      body = response.parsed_body["case"]
      expect(body["case_number"]).to eq(atcp_case.case_number)
      expect(body["case_type"]).to eq("Hardware defect")
      expect(body["severity"]).to eq("Medium")
      expect(body["status"]).to eq("Open")
      expect(body["source"]).to eq("manual")
      expect(body["reporter_name"]).to eq(atcp_case.reporter_name)
      expect(body["reporter_branch_name"]).to eq(
        "#{branch.name} (#{branch.code})"
      )
      expect(body["frequency"]).to eq("Always")
      expect(body["reproducibility"]).to eq("Reproducible")
      expect(body["bios_version"]).to eq("1.2.3")
      expect(body["os_driver_info"]).to eq("Windows 11")
      expect(body["products"]).to eq(
        [
          {
            "id" => product.id,
            "name" => product.name,
            "sku" => product.sku_code
          }
        ]
      )
      expect(body["created_by"]).to eq(
        {
          "id" => internal_user.id,
          "username" => internal_user.username,
          "name" => internal_user.name
        }
      )
      expect(body["assignee"]["username"]).to eq(other_internal_user.username)
      expect(body["aging_days"]).to eq(5)
      expect(body["waiting"]["label"]).to eq("Waiting for unit")
      expect(body["waiting"]["days"]).to eq(2)

      updates = body["updates"]
      expect(updates.map { |update| update["id"] }).to eq(
        [waiting_update.id, system_update.id]
      )

      system_json = updates.last
      expect(system_json["is_system"]).to eq(true)
      expect(system_json["system_event"]).to eq("status_changed")
      expect(system_json["from_value"]).to eq("Open")
      expect(system_json["to_value"]).to eq("In Progress")

      attachment_json = updates.first["attachments"].first
      expect(attachment_json["upload_id"]).to eq(upload.id)
      expect(attachment_json["url"]).to eq(upload.url)
      expect(attachment_json["original_filename"]).to eq(
        upload.original_filename
      )
      expect(attachment_json["human_filesize"]).to eq(upload.human_filesize)
      expect(attachment_json["is_image"]).to eq(true)
    end

    it "uses closed_at for aging and hides waiting for closed cases" do
      atcp_case =
        create_open_case!(
          opened_at: 6.days.ago,
          status: "Closed",
          close_reason: "Duplicate",
          closed_at: 2.days.ago
        )
      Fabricate(
        :atcp_case_update,
        atcp_case: atcp_case,
        user: internal_user,
        update_type: "Waiting for unit",
        created_at: 4.days.ago
      )

      get "/atcp/cases/#{atcp_case.id}.json"

      body = response.parsed_body["case"]
      expect(body["aging_days"]).to eq(4)
      expect(body["waiting"]).to be_nil
    end

    it "does not grow the query count with more updates" do
      atcp_case = create_open_case!
      2.times do |index|
        entry =
          Fabricate(
            :atcp_case_update,
            atcp_case: atcp_case,
            user: internal_user,
            created_at: (index + 1).minutes.ago
          )
        next if index.nonzero?

        upload = Fabricate(:upload, user: internal_user)
        AtcpCaseAttachment.create!(
          case_id: atcp_case.id,
          update_id: entry.id,
          upload_id: upload.id
        )
      end

      get "/atcp/cases/#{atcp_case.id}.json"
      expect(response.status).to eq(200)

      queries_for_small =
        track_sql_queries { get "/atcp/cases/#{atcp_case.id}.json" }
      expect(response.status).to eq(200)

      10.times do |index|
        entry =
          Fabricate(
            :atcp_case_update,
            atcp_case: atcp_case,
            user: internal_user,
            created_at: (index + 3).minutes.ago
          )
        next if index.odd?

        upload = Fabricate(:upload, user: internal_user)
        AtcpCaseAttachment.create!(
          case_id: atcp_case.id,
          update_id: entry.id,
          upload_id: upload.id
        )
      end

      queries_for_large =
        track_sql_queries { get "/atcp/cases/#{atcp_case.id}.json" }

      expect(response.status).to eq(200)
      expect(queries_for_large.size).to eq(queries_for_small.size)
    end

    it "returns 404 for a missing case" do
      get "/atcp/cases/0.json"

      expect(response.status).to eq(404)
    end
  end

  describe "#form_options" do
    before { sign_in(internal_user) }

    it "returns form options and only active, non-deleted branches" do
      active_branch =
        Fabricate(
          :atcp_branch,
          name: "Jakarta",
          code: "JKT-01",
          status: "active"
        )
      Fabricate(
        :atcp_branch,
        name: "Bandung",
        code: "BDG-01",
        status: "inactive"
      )
      deleted_branch =
        Fabricate(
          :atcp_branch,
          name: "Surabaya",
          code: "SBY-01",
          status: "active"
        )
      deleted_branch.update_column(:deleted_at, 1.day.ago)

      get "/atcp/cases/form_options.json"

      expect(response.status).to eq(200)
      body = response.parsed_body
      expect(body["case_types"]).to eq(AtcpCase::CASE_TYPES)
      expect(body["severities"]).to eq(AtcpCase::SEVERITIES)
      expect(body["statuses"]).to eq(AtcpCase::STATUSES)
      expect(body["close_reasons"]).to eq(AtcpCase::CLOSE_REASONS)
      expect(body["frequencies"]).to eq(AtcpCase::FREQUENCIES)
      expect(body["reproducibilities"]).to eq(AtcpCase::REPRODUCIBILITIES)
      expect(body["branches"]).to eq(
        [
          {
            "id" => active_branch.id,
            "name" => "Jakarta",
            "code" => "JKT-01",
            "label" => "Jakarta (JKT-01)"
          }
        ]
      )
      expect(body["upload"]["extensions"]).to eq(
        SiteSetting.atcp_case_attachment_extensions.split("|")
      )
      expect(body["upload"]["max_mb"]).to eq(
        SiteSetting.atcp_case_max_attachment_mb
      )
    end
  end

  describe "#pic_candidates" do
    before { sign_in(internal_user) }

    it "groups internal members by configured departments" do
      SiteSetting.atcp_case_pic_departments =
        "Support: #{other_internal_user.username}"

      get "/atcp/cases/pic_candidates.json"

      expect(response.status).to eq(200)
      groups = response.parsed_body["groups"]
      support = groups.find { |entry| entry["name"] == "Support" }
      expect(support["users"]).to eq(
        [
          {
            "id" => other_internal_user.id,
            "username" => other_internal_user.username,
            "name" => other_internal_user.name
          }
        ]
      )

      other = groups.last
      expect(other["name"]).to eq("Other")
      other_user_ids = other["users"].map { |user| user["id"] }
      expect(other_user_ids).to include(internal_user.id, admin_user.id)
      expect(other_user_ids).not_to include(other_internal_user.id, outsider.id)
    end
  end

  describe "#create" do
    before { sign_in(internal_user) }

    def valid_case_params(overrides = {})
      {
        title: "Device keeps restarting",
        case_type: "Hardware defect",
        severity: "High",
        source: "Branch report",
        symptom: "Unit restarts every 10 minutes",
        product_ids: [product.id]
      }.merge(overrides)
    end

    it "creates a case with a generated number, snapshots and audit log" do
      branch =
        Fabricate(
          :atcp_branch,
          name: "Jakarta",
          code: "JKT-01",
          status: "active"
        )
      year = Time.now.in_time_zone("Asia/Jakarta").year

      post "/atcp/cases.json",
           params:
             valid_case_params(
               reporter_name: "Andi",
               reporter_branch_id: branch.id,
               assignee_id: other_internal_user.id,
               product_ids: [product.id, second_product.id]
             )

      expect(response.status).to eq(200)
      body = response.parsed_body["case"]
      expect(body["case_number"]).to eq("CASE-#{year}-0001")
      expect(body["status"]).to eq("Open")
      expect(body["reporter_branch_name"]).to eq("Jakarta (JKT-01)")
      expect(body["products"]).to contain_exactly(
        {
          "id" => product.id,
          "name" => product.name,
          "sku" => product.sku_code
        },
        {
          "id" => second_product.id,
          "name" => second_product.name,
          "sku" => second_product.sku_code
        }
      )
      expect(body["assignee"]["id"]).to eq(other_internal_user.id)

      atcp_case = AtcpCase.find(body["id"])
      expect(atcp_case.created_by_id).to eq(internal_user.id)
      expect(atcp_case.opened_at).to be_present
      expect(
        AtcpCaseProduct
          .where(case_id: atcp_case.id)
          .map { |entry| [entry.product_name, entry.sku_code] }
      ).to contain_exactly(
        [product.name, product.sku_code],
        [second_product.name, second_product.sku_code]
      )
      expect(UserHistory.where(custom_type: "atcp_case_created").count).to eq(1)
    end

    it "generates sequential case numbers" do
      year = Time.now.in_time_zone("Asia/Jakarta").year

      post "/atcp/cases.json", params: valid_case_params

      expect(response.parsed_body["case"]["case_number"]).to eq(
        "CASE-#{year}-0001"
      )

      post "/atcp/cases.json", params: valid_case_params

      expect(response.parsed_body["case"]["case_number"]).to eq(
        "CASE-#{year}-0002"
      )
    end

    it "always opens the case regardless of the status param" do
      post "/atcp/cases.json",
           params:
             valid_case_params(
               status: "Closed",
               close_reason: "Resolved",
               solution: "Fixed"
             )

      expect(response.status).to eq(200)
      expect(response.parsed_body["case"]["status"]).to eq("Open")
    end

    it "returns per-field validation errors" do
      post "/atcp/cases.json", params: {}

      expect(response.status).to eq(422)
      errors = response.parsed_body["errors"]
      expect(errors["title"]).to include(
        I18n.t("atcp_case.errors.title_required")
      )
      expect(errors["case_type"]).to include(
        I18n.t("atcp_case.errors.case_type_invalid")
      )
      expect(errors["severity"]).to include(
        I18n.t("atcp_case.errors.severity_invalid")
      )
      expect(errors["source"]).to include(
        I18n.t("atcp_case.errors.source_required")
      )
      expect(errors["symptom"]).to include(
        I18n.t("atcp_case.errors.symptom_required")
      )
      expect(errors["product_ids"]).to include(
        I18n.t("atcp_case.errors.products_required")
      )
      expect(AtcpCase.count).to eq(0)
    end

    it "rejects unknown products" do
      post "/atcp/cases.json",
           params: valid_case_params(product_ids: [product.id, 999_999])

      expect(response.status).to eq(422)
      expect(response.parsed_body["errors"]["product_ids"]).to include(
        I18n.t("atcp_case.errors.products_unknown")
      )
      expect(AtcpCase.count).to eq(0)

      post "/atcp/cases.json",
           params: valid_case_params(product_ids: ["not-a-number"])

      expect(response.status).to eq(422)
      expect(response.parsed_body["errors"]["product_ids"]).to include(
        I18n.t("atcp_case.errors.products_unknown")
      )
    end

    it "rejects an inactive or deleted reporter branch" do
      inactive_branch = Fabricate(:atcp_branch, status: "inactive")
      deleted_branch = Fabricate(:atcp_branch, status: "active")
      deleted_branch.update_column(:deleted_at, 1.day.ago)

      [inactive_branch, deleted_branch].each do |branch|
        post "/atcp/cases.json",
             params: valid_case_params(reporter_branch_id: branch.id)

        expect(response.status).to eq(422)
        expect(response.parsed_body["errors"]["reporter_branch_id"]).to include(
          I18n.t("atcp_case.errors.reporter_branch_invalid")
        )
      end
    end

    it "rejects an assignee outside the internal community" do
      post "/atcp/cases.json",
           params: valid_case_params(assignee_id: outsider.id)

      expect(response.status).to eq(422)
      expect(response.parsed_body["errors"]["assignee_id"]).to include(
        I18n.t("atcp_case.errors.assignee_invalid")
      )
    end

    it "rejects suspended or deactivated assignees" do
      suspended = Fabricate(:user)
      internal_group.add(suspended)
      suspended.update!(suspended_till: 1.year.from_now)

      post "/atcp/cases.json",
           params: valid_case_params(assignee_id: suspended.id)

      expect(response.status).to eq(422)
      expect(response.parsed_body["errors"]["assignee_id"]).to include(
        I18n.t("atcp_case.errors.assignee_invalid")
      )

      deactivated = Fabricate(:user)
      internal_group.add(deactivated)
      deactivated.update!(active: false)

      post "/atcp/cases.json",
           params: valid_case_params(assignee_id: deactivated.id)

      expect(response.status).to eq(422)
      expect(response.parsed_body["errors"]["assignee_id"]).to include(
        I18n.t("atcp_case.errors.assignee_invalid")
      )
    end

    it "rejects malformed reporter branch and assignee ids" do
      post "/atcp/cases.json",
           params:
             valid_case_params(
               reporter_branch_id: [1],
               assignee_id: {
                 "nested" => "1"
               }
             )

      expect(response.status).to eq(422)
      expect(response.parsed_body["errors"]["reporter_branch_id"]).to include(
        I18n.t("atcp_case.errors.reporter_branch_invalid")
      )
      expect(response.parsed_body["errors"]["assignee_id"]).to include(
        I18n.t("atcp_case.errors.assignee_invalid")
      )
      expect(AtcpCase.count).to eq(0)
    end

    it "limits title, reporter name and BIOS version to 255 characters" do
      post "/atcp/cases.json", params: valid_case_params(title: "a" * 256)

      expect(response.status).to eq(422)
      expect(response.parsed_body["errors"]["title"]).to include(
        I18n.t("atcp_case.errors.title_too_long")
      )

      post "/atcp/cases.json",
           params: valid_case_params(reporter_name: "a" * 256)

      expect(response.status).to eq(422)
      expect(response.parsed_body["errors"]["reporter_name"]).to include(
        I18n.t("atcp_case.errors.reporter_name_too_long")
      )

      post "/atcp/cases.json",
           params: valid_case_params(bios_version: "a" * 256)

      expect(response.status).to eq(422)
      expect(response.parsed_body["errors"]["bios_version"]).to include(
        I18n.t("atcp_case.errors.bios_version_too_long")
      )
      expect(AtcpCase.count).to eq(0)
    end

    it "accepts an optional BIOS version" do
      post "/atcp/cases.json", params: valid_case_params(bios_version: "1.2.3")

      expect(response.status).to eq(200)
      expect(response.parsed_body["case"]["bios_version"]).to eq("1.2.3")
    end

    it "rolls back the case when a product snapshot fails" do
      allow(AtcpCaseProduct).to receive(:create!).and_raise(
        ActiveRecord::RecordInvalid.new(AtcpCaseProduct.new)
      )

      post "/atcp/cases.json", params: valid_case_params

      expect(response.status).to eq(422)
      expect(AtcpCase.count).to eq(0)
      expect(AtcpCaseProduct.count).to eq(0)
      expect(UserHistory.where(custom_type: "atcp_case_created").count).to eq(0)
    end
  end

  describe "#update" do
    before { sign_in(internal_user) }

    it "updates the allowed fields" do
      branch =
        Fabricate(
          :atcp_branch,
          name: "Jakarta",
          code: "JKT-01",
          status: "active"
        )
      atcp_case = create_open_case!
      Fabricate(:atcp_case_product, atcp_case: atcp_case, atcp_product: product)

      put "/atcp/cases/#{atcp_case.id}.json",
          params: {
            title: "Updated title",
            case_type: "Performance",
            severity: "Critical",
            source: "QA report",
            symptom: "Updated symptom",
            frequency: "Intermittent",
            reproducibility: "Reproducible",
            bios_version: "2.0.0",
            os_driver_info: "Windows 11",
            non_trigger_conditions: "Only on cold boot",
            root_cause_summary: "Bad RAM",
            solution: "Replace RAM",
            workaround: "Use a single stick",
            conclusion: "Hardware fault",
            reporter_name: "Budi",
            reporter_branch_id: branch.id,
            assignee_id: other_internal_user.id
          }

      expect(response.status).to eq(200)
      body = response.parsed_body["case"]
      expect(body["title"]).to eq("Updated title")
      expect(body["case_type"]).to eq("Performance")
      expect(body["severity"]).to eq("Critical")
      expect(body["source"]).to eq("QA report")
      expect(body["frequency"]).to eq("Intermittent")
      expect(body["reproducibility"]).to eq("Reproducible")
      expect(body["bios_version"]).to eq("2.0.0")
      expect(body["non_trigger_conditions"]).to eq("Only on cold boot")
      expect(body["root_cause_summary"]).to eq("Bad RAM")
      expect(body["solution"]).to eq("Replace RAM")
      expect(body["workaround"]).to eq("Use a single stick")
      expect(body["conclusion"]).to eq("Hardware fault")
      expect(body["reporter_name"]).to eq("Budi")
      expect(body["reporter_branch_name"]).to eq("Jakarta (JKT-01)")
      expect(body["assignee"]["id"]).to eq(other_internal_user.id)

      atcp_case.reload
      expect(atcp_case.title).to eq("Updated title")
      expect(atcp_case.assignee_id).to eq(other_internal_user.id)
      expect(atcp_case.reporter_branch_id).to eq(branch.id)
    end

    it "records severity and assignee changes as system entries" do
      atcp_case =
        create_open_case!(severity: "Low", assignee: other_internal_user)

      put "/atcp/cases/#{atcp_case.id}.json",
          params: {
            severity: "High",
            assignee_id: internal_user.id
          }

      expect(response.status).to eq(200)
      entries =
        AtcpCaseUpdate.where(case_id: atcp_case.id, is_system: true).order(:id)
      expect(entries.map(&:system_event)).to eq(
        %w[severity_changed assignee_changed]
      )
      expect(entries.first.from_value).to eq("Low")
      expect(entries.first.to_value).to eq("High")
      expect(entries.last.from_value).to eq(other_internal_user.username)
      expect(entries.last.to_value).to eq(internal_user.username)
    end

    it "does not record system entries when values do not change" do
      atcp_case =
        create_open_case!(severity: "High", assignee: other_internal_user)

      put "/atcp/cases/#{atcp_case.id}.json",
          params: {
            title: "Still here",
            severity: "High",
            assignee_id: other_internal_user.id
          }

      expect(response.status).to eq(200)
      expect(AtcpCaseUpdate.where(case_id: atcp_case.id).count).to eq(0)
    end

    it "clears the assignee when the value is blank" do
      atcp_case = create_open_case!(assignee: other_internal_user)

      put "/atcp/cases/#{atcp_case.id}.json", params: { assignee_id: "" }

      expect(response.status).to eq(200)
      expect(response.parsed_body["case"]["assignee"]).to be_nil

      entry = AtcpCaseUpdate.find_by(case_id: atcp_case.id)
      expect(entry.system_event).to eq("assignee_changed")
      expect(entry.from_value).to eq(other_internal_user.username)
      expect(entry.to_value).to eq("Unassigned")
    end

    it "ignores protected fields" do
      atcp_case = create_open_case!
      original =
        atcp_case.attributes.slice(
          "case_number",
          "status",
          "created_by_id",
          "opened_at",
          "closed_at",
          "close_reason"
        )

      put "/atcp/cases/#{atcp_case.id}.json",
          params: {
            title: "New title",
            status: "Closed",
            case_number: "CASE-1999-0001",
            created_by_id: admin_user.id,
            opened_at: 1.year.ago.iso8601,
            closed_at: Time.zone.now.iso8601,
            close_reason: "Resolved"
          }

      expect(response.status).to eq(200)
      atcp_case.reload
      expect(
        atcp_case.attributes.slice(
          "case_number",
          "status",
          "created_by_id",
          "opened_at",
          "closed_at",
          "close_reason"
        )
      ).to eq(original)
      expect(atcp_case.title).to eq("New title")
    end

    it "replaces case products, keeping snapshots of kept products" do
      atcp_case = create_open_case!
      Fabricate(:atcp_case_product, atcp_case: atcp_case, atcp_product: product)
      Fabricate(
        :atcp_case_product,
        atcp_case: atcp_case,
        atcp_product: second_product
      )
      original_name = product.name

      product.update_columns(name: "Renamed product")

      put "/atcp/cases/#{atcp_case.id}.json",
          params: {
            product_ids: [product.id]
          }

      expect(response.status).to eq(200)
      links = AtcpCaseProduct.where(case_id: atcp_case.id)
      expect(links.pluck(:product_id)).to eq([product.id])
      expect(links.first.product_name).to eq(original_name)

      put "/atcp/cases/#{atcp_case.id}.json",
          params: {
            product_ids: [product.id, second_product.id]
          }

      expect(response.status).to eq(200)
      expect(
        AtcpCaseProduct.where(case_id: atcp_case.id).pluck(:product_id)
      ).to contain_exactly(product.id, second_product.id)
    end

    it "keeps snapshot rows whose product was deleted" do
      atcp_case = create_open_case!
      Fabricate(:atcp_case_product, atcp_case: atcp_case, atcp_product: product)
      Fabricate(
        :atcp_case_product,
        atcp_case: atcp_case,
        atcp_product: second_product
      )
      snapshot_name = product.name
      product.destroy!

      put "/atcp/cases/#{atcp_case.id}.json",
          params: {
            product_ids: [second_product.id]
          }

      expect(response.status).to eq(200)
      links = AtcpCaseProduct.where(case_id: atcp_case.id).order(:id)
      expect(links.size).to eq(2)

      orphan = links.find { |link| link.product_id.nil? }
      expect(orphan.product_name).to eq(snapshot_name)
      expect(
        links.reject { |link| link.product_id.nil? }.map(&:product_id)
      ).to eq([second_product.id])
    end

    it "requires at least one product when product_ids is sent" do
      atcp_case = create_open_case!
      Fabricate(:atcp_case_product, atcp_case: atcp_case, atcp_product: product)

      put "/atcp/cases/#{atcp_case.id}.json", params: { product_ids: [""] }

      expect(response.status).to eq(422)
      expect(response.parsed_body["errors"]["product_ids"]).to include(
        I18n.t("atcp_case.errors.products_required")
      )
      expect(AtcpCaseProduct.where(case_id: atcp_case.id).count).to eq(1)
    end

    it "validates the sent fields" do
      atcp_case = create_open_case!

      put "/atcp/cases/#{atcp_case.id}.json",
          params: {
            severity: "Urgent",
            frequency: "Sometimes",
            reproducibility: "Maybe"
          }

      expect(response.status).to eq(422)
      errors = response.parsed_body["errors"]
      expect(errors["severity"]).to include(
        I18n.t("atcp_case.errors.severity_invalid")
      )
      expect(errors["frequency"]).to include(
        I18n.t("atcp_case.errors.frequency_invalid")
      )
      expect(errors["reproducibility"]).to include(
        I18n.t("atcp_case.errors.reproducibility_invalid")
      )
    end

    it "validates sent text lengths" do
      atcp_case = create_open_case!

      put "/atcp/cases/#{atcp_case.id}.json",
          params: {
            title: "a" * 256,
            bios_version: "b" * 256
          }

      expect(response.status).to eq(422)
      errors = response.parsed_body["errors"]
      expect(errors["title"]).to include(
        I18n.t("atcp_case.errors.title_too_long")
      )
      expect(errors["bios_version"]).to include(
        I18n.t("atcp_case.errors.bios_version_too_long")
      )
    end

    it "rejects an ineligible assignee" do
      atcp_case = create_open_case!

      put "/atcp/cases/#{atcp_case.id}.json",
          params: {
            assignee_id: outsider.id
          }

      expect(response.status).to eq(422)
      expect(response.parsed_body["errors"]["assignee_id"]).to include(
        I18n.t("atcp_case.errors.assignee_invalid")
      )
    end

    it "allows clearing frequency and reproducibility" do
      atcp_case =
        create_open_case!(frequency: "Always", reproducibility: "Reproducible")

      put "/atcp/cases/#{atcp_case.id}.json",
          params: {
            frequency: "",
            reproducibility: ""
          }

      expect(response.status).to eq(200)
      body = response.parsed_body["case"]
      expect(body["frequency"]).to be_nil
      expect(body["reproducibility"]).to be_nil
    end

    it "rejects updates to a closed case" do
      atcp_case =
        create_open_case!(
          status: "Closed",
          close_reason: "Duplicate",
          closed_at: 1.hour.ago
        )

      put "/atcp/cases/#{atcp_case.id}.json", params: { title: "Nope" }

      expect(response.status).to eq(422)
      expect(response.parsed_body["errors"]["base"]).to include(
        I18n.t("atcp_case.errors.case_closed")
      )
      expect(atcp_case.reload.title).not_to eq("Nope")
    end

    it "re-checks the closed status inside the lock" do
      atcp_case = create_open_case!
      stale = AtcpCase.find(atcp_case.id)
      atcp_case.update_columns(
        status: "Closed",
        close_reason: "Duplicate",
        closed_at: 1.hour.ago
      )
      allow_any_instance_of(Atcp::CasesController).to receive(
        :find_case!
      ).and_return(stale)

      put "/atcp/cases/#{atcp_case.id}.json", params: { title: "Nope" }

      expect(response.status).to eq(422)
      expect(response.parsed_body["errors"]["base"]).to include(
        I18n.t("atcp_case.errors.case_closed")
      )
      atcp_case.reload
      expect(atcp_case.title).not_to eq("Nope")
      expect(AtcpCaseUpdate.where(case_id: atcp_case.id).count).to eq(0)
    end

    it "renders model validation errors with field messages" do
      atcp_case = create_open_case!
      record = AtcpCase.new
      record.errors.add(:title, "is taken")
      allow_any_instance_of(AtcpCase).to receive(:save!).and_raise(
        ActiveRecord::RecordInvalid.new(record)
      )

      put "/atcp/cases/#{atcp_case.id}.json", params: { title: "Nope" }

      expect(response.status).to eq(422)
      expect(response.parsed_body["errors"]["title"]).to include("is taken")
    end

    it "returns 404 for a missing case" do
      put "/atcp/cases/0.json", params: { title: "Nope" }

      expect(response.status).to eq(404)
    end
  end

  describe "#close" do
    before { sign_in(internal_user) }

    it "closes the case with a reason, timestamp and system entry" do
      atcp_case = create_open_case!(status: "In Progress")

      post "/atcp/cases/#{atcp_case.id}/close.json",
           params: {
             close_reason: "Cannot Reproduce"
           }

      expect(response.status).to eq(200)
      body = response.parsed_body["case"]
      expect(body["status"]).to eq("Closed")
      expect(body["close_reason"]).to eq("Cannot Reproduce")
      expect(body["closed_at"]).to be_present

      atcp_case.reload
      expect(atcp_case.status).to eq("Closed")
      expect(atcp_case.closed_at).to be_present

      entry =
        AtcpCaseUpdate.find_by(case_id: atcp_case.id, system_event: "closed")
      expect(entry.from_value).to eq("In Progress")
      expect(entry.to_value).to eq("Closed")
      expect(entry.is_system).to eq(true)
      expect(entry.details["close_reason"]).to eq("Cannot Reproduce")
    end

    it "requires a valid close reason" do
      atcp_case = create_open_case!

      post "/atcp/cases/#{atcp_case.id}/close.json", params: {}

      expect(response.status).to eq(422)
      expect(response.parsed_body["errors"]["close_reason"]).to include(
        I18n.t("atcp_case.errors.close_reason_required")
      )

      post "/atcp/cases/#{atcp_case.id}/close.json",
           params: {
             close_reason: "Bogus"
           }

      expect(response.status).to eq(422)
      expect(response.parsed_body["errors"]["close_reason"]).to include(
        I18n.t("atcp_case.errors.close_reason_invalid")
      )
      expect(atcp_case.reload.status).to eq("Open")
    end

    it "requires a solution when closing as Resolved" do
      atcp_case = create_open_case!

      post "/atcp/cases/#{atcp_case.id}/close.json",
           params: {
             close_reason: "Resolved"
           }

      expect(response.status).to eq(422)
      expect(response.parsed_body["errors"]["solution"]).to include(
        I18n.t("atcp_case.errors.solution_required")
      )
    end

    it "accepts a solution and findings when closing as Resolved" do
      atcp_case = create_open_case!

      post "/atcp/cases/#{atcp_case.id}/close.json",
           params: {
             close_reason: "Resolved",
             solution: "Replace the SSD",
             root_cause_summary: "SSD wear",
             workaround: "Boot from USB",
             conclusion: "RMA approved"
           }

      expect(response.status).to eq(200)
      body = response.parsed_body["case"]
      expect(body["solution"]).to eq("Replace the SSD")
      expect(body["root_cause_summary"]).to eq("SSD wear")
      expect(body["workaround"]).to eq("Boot from USB")
      expect(body["conclusion"]).to eq("RMA approved")
    end

    it "uses an existing solution when closing as Resolved" do
      atcp_case = create_open_case!(solution: "Reseat the memory")

      post "/atcp/cases/#{atcp_case.id}/close.json",
           params: {
             close_reason: "Resolved"
           }

      expect(response.status).to eq(200)
      expect(response.parsed_body["case"]["solution"]).to eq(
        "Reseat the memory"
      )
    end

    it "rejects closing an already closed case" do
      atcp_case =
        create_open_case!(
          status: "Closed",
          close_reason: "Duplicate",
          closed_at: 1.hour.ago
        )

      post "/atcp/cases/#{atcp_case.id}/close.json",
           params: {
             close_reason: "Resolved",
             solution: "Fixed"
           }

      expect(response.status).to eq(422)
      expect(response.parsed_body["errors"]["base"]).to include(
        I18n.t("atcp_case.errors.already_closed")
      )
    end

    it "re-checks the closed status inside the lock" do
      atcp_case = create_open_case!
      stale = AtcpCase.find(atcp_case.id)
      atcp_case.update_columns(
        status: "Closed",
        close_reason: "Duplicate",
        closed_at: 1.hour.ago
      )
      allow_any_instance_of(Atcp::CasesController).to receive(
        :find_case!
      ).and_return(stale)

      post "/atcp/cases/#{atcp_case.id}/close.json",
           params: {
             close_reason: "Resolved",
             solution: "Fixed"
           }

      expect(response.status).to eq(422)
      expect(response.parsed_body["errors"]["base"]).to include(
        I18n.t("atcp_case.errors.already_closed")
      )
      atcp_case.reload
      expect(atcp_case.close_reason).to eq("Duplicate")
      expect(atcp_case.closed_at).to be_present
      expect(AtcpCaseUpdate.where(case_id: atcp_case.id).count).to eq(0)
    end

    it "returns 404 for a missing case" do
      post "/atcp/cases/0/close.json", params: { close_reason: "Duplicate" }

      expect(response.status).to eq(404)
    end
  end

  describe "#reopen" do
    before { sign_in(internal_user) }

    def closed_case(overrides = {})
      create_open_case!(
        {
          status: "Closed",
          close_reason: "Duplicate",
          closed_at: 1.hour.ago
        }.merge(overrides)
      )
    end

    it "reopens a closed case, resetting the close fields" do
      atcp_case = closed_case(solution: "Old solution")

      post "/atcp/cases/#{atcp_case.id}/reopen.json",
           params: {
             reason: "Customer reports the issue again"
           }

      expect(response.status).to eq(200)
      body = response.parsed_body["case"]
      expect(body["status"]).to eq("In Progress")
      expect(body["closed_at"]).to be_nil
      expect(body["close_reason"]).to be_nil
      expect(body["solution"]).to eq("Old solution")

      atcp_case.reload
      expect(atcp_case.closed_at).to be_nil
      expect(atcp_case.close_reason).to be_nil

      entry =
        AtcpCaseUpdate.find_by(case_id: atcp_case.id, system_event: "reopened")
      expect(entry.from_value).to eq("Closed")
      expect(entry.to_value).to eq("In Progress")
      expect(entry.body).to eq("Customer reports the issue again")
      expect(entry.details["previous_close_reason"]).to eq("Duplicate")
      expect(entry.details["previous_closed_at"]).to be_present
    end

    it "requires a reason" do
      atcp_case = closed_case

      post "/atcp/cases/#{atcp_case.id}/reopen.json", params: { reason: "  " }

      expect(response.status).to eq(422)
      expect(response.parsed_body["errors"]["reason"]).to include(
        I18n.t("atcp_case.errors.reopen_reason_required")
      )

      post "/atcp/cases/#{atcp_case.id}/reopen.json",
           params: {
             reason: "a" * 2001
           }

      expect(response.status).to eq(422)
      expect(response.parsed_body["errors"]["reason"]).to include(
        I18n.t("atcp_case.errors.reopen_reason_too_long")
      )
    end

    it "rejects reopening a case that is not closed" do
      atcp_case = create_open_case!

      post "/atcp/cases/#{atcp_case.id}/reopen.json",
           params: {
             reason: "Please reopen"
           }

      expect(response.status).to eq(422)
      expect(response.parsed_body["errors"]["base"]).to include(
        I18n.t("atcp_case.errors.not_closed")
      )
    end

    it "re-checks the closed status inside the lock" do
      atcp_case = closed_case
      stale = AtcpCase.find(atcp_case.id)
      atcp_case.update_columns(
        status: "Open",
        closed_at: nil,
        close_reason: nil
      )
      allow_any_instance_of(Atcp::CasesController).to receive(
        :find_case!
      ).and_return(stale)

      post "/atcp/cases/#{atcp_case.id}/reopen.json",
           params: {
             reason: "Issue persists"
           }

      expect(response.status).to eq(422)
      expect(response.parsed_body["errors"]["base"]).to include(
        I18n.t("atcp_case.errors.not_closed")
      )
      atcp_case.reload
      expect(atcp_case.status).to eq("Open")
      expect(atcp_case.closed_at).to be_nil
      expect(AtcpCaseUpdate.where(case_id: atcp_case.id).count).to eq(0)
    end

    it "supports repeated close and reopen cycles" do
      atcp_case = closed_case
      first_closed_at = atcp_case.reload.closed_at

      post "/atcp/cases/#{atcp_case.id}/reopen.json",
           params: {
             reason: "Issue persists"
           }
      expect(response.status).to eq(200)

      post "/atcp/cases/#{atcp_case.id}/close.json",
           params: {
             close_reason: "Cancelled"
           }
      expect(response.status).to eq(200)

      entry =
        AtcpCaseUpdate
          .where(case_id: atcp_case.id, system_event: "reopened")
          .order(:id)
          .last
      expect(Time.zone.parse(entry.details["previous_closed_at"])).to be_within(
        1.second
      ).of(first_closed_at)
      expect(atcp_case.reload.closed_at).to be >= first_closed_at
    end

    it "returns 404 for a missing case" do
      post "/atcp/cases/0/reopen.json", params: { reason: "Reopen" }

      expect(response.status).to eq(404)
    end
  end
end
