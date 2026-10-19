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
        [{ "name" => product.name, "sku" => product.sku_code }]
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
        [{ "name" => product.name, "sku" => product.sku_code }]
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
      expect(body["update_labels"]).to eq(
        SiteSetting.atcp_case_update_labels.split("|")
      )
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
        { "name" => product.name, "sku" => product.sku_code },
        { "name" => second_product.name, "sku" => second_product.sku_code }
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
end
