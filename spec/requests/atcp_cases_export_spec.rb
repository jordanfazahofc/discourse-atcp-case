# frozen_string_literal: true

require "zip"

RSpec.describe "Atcp case export" do
  fab!(:internal_group, :group)
  fab!(:internal_user, :user)
  fab!(:outsider, :user)
  fab!(:moderator)
  fab!(:admin)

  before do
    enable_current_plugin
    internal_group.add(internal_user)
    SiteSetting.atcp_internal_groups = internal_group.id.to_s
  end

  def create_case!(attrs = {})
    Fabricate(:atcp_case, { created_by: internal_user }.merge(attrs))
  end

  def add_product!(atcp_case, name:, sku:)
    product = Fabricate(:atcp_product, sku_code: sku)
    Fabricate(
      :atcp_case_product,
      atcp_case: atcp_case,
      atcp_product: product,
      product_name: name,
      sku_code: sku
    )
    product
  end

  def xlsx_entries
    Zip::File.open_buffer(response.body).entries
  end

  def xlsx_sheet
    entry = xlsx_entries.find { |e| e.name =~ %r{xl/worksheets/sheet1\.xml} }
    Nokogiri.XML(entry.get_input_stream.read)
  end

  def xlsx_shared_strings
    entry = xlsx_entries.find { |e| e.name == "xl/sharedStrings.xml" }
    return [] if entry.nil?

    Nokogiri
      .XML(entry.get_input_stream.read)
      .xpath("//*[local-name()='si']")
      .map { |si| si.xpath(".//*[local-name()='t']").map(&:text).join("") }
  end

  def xlsx_rows
    shared = xlsx_shared_strings

    xlsx_sheet
      .xpath("//*[local-name()='row']")
      .map do |row|
        row
          .xpath("./*[local-name()='c']")
          .map do |cell|
            if cell["t"] == "s"
              shared[cell.xpath("./*[local-name()='v']").text.to_i]
            else
              cell.xpath(".//*[local-name()='t']").map(&:text).join.presence ||
                cell.xpath("./*[local-name()='v']").text
            end
          end
      end
  end

  def data_rows
    xlsx_rows.drop(1)
  end

  def exported_case_numbers
    data_rows.map(&:first)
  end

  describe "access" do
    it "returns 200 for Internal group members" do
      create_case!

      sign_in(internal_user)
      get "/atcp/cases/export"

      expect(response.status).to eq(200)
      expect(response.media_type).to eq(AtcpCaseExcelExport::XLSX_MIME)
      expect(data_rows.size).to eq(1)
    end

    it "returns 200 for admins outside the Internal group" do
      create_case!

      sign_in(admin)
      get "/atcp/cases/export"

      expect(response.status).to eq(200)
      expect(data_rows.size).to eq(1)
    end

    it "returns 403 for anonymous users" do
      create_case!

      get "/atcp/cases/export"

      expect(response.status).to eq(403)
    end

    it "returns 403 for moderators outside the Internal group" do
      create_case!

      sign_in(moderator)
      get "/atcp/cases/export"

      expect(response.status).to eq(403)
    end
  end

  describe "workbook contents" do
    before { sign_in(internal_user) }

    it "writes the headers in the required order" do
      create_case!
      get "/atcp/cases/export"

      expect(xlsx_rows.first).to eq(
        [
          "Case No.",
          "Date Opened",
          "Date Closed",
          "Title",
          "Type",
          "Status",
          "Product",
          "Source",
          "Reporter",
          "PIC",
          "Affected Units",
          "BIOS",
          "Root Cause",
          "Solution",
          "Aging (days)"
        ]
      )
    end

    it "writes every data cell as an Excel string cell" do
      create_case!
      get "/atcp/cases/export"

      data_cell_types =
        xlsx_sheet
          .xpath("//*[local-name()='row']")
          .drop(1)
          .flat_map do |row|
            row.xpath("./*[local-name()='c']").map { |cell| cell["t"] }
          end

      expect(data_cell_types).to all(eq("s"))
    end

    it "keeps empty values as a dash" do
      create_case!(
        title: "Open case without PIC",
        root_cause_summary: nil,
        solution: nil,
        bios_version: nil
      )
      get "/atcp/cases/export"

      row = data_rows.first
      expect(row[2]).to eq("-") # Date Closed
      expect(row[9]).to eq("-") # PIC
      expect(row[10]).to eq("-") # Affected Units
      expect(row[11]).to eq("-") # BIOS
      expect(row[12]).to eq("-") # Root Cause
      expect(row[13]).to eq("-") # Solution
    end

    it "exports the case creator as Reporter and the assignee as PIC" do
      reporter =
        Fabricate(:user, username: "case_reporter", name: "Case Reporter")
      pic = Fabricate(:user, username: "case_pic", name: "Case PIC")
      create_case!(created_by: reporter, assignee: pic)
      get "/atcp/cases/export"

      row = data_rows.first
      expect(row[8]).to eq("Case Reporter")
      expect(row[9]).to eq("Case PIC")
    end

    it "formats dates in Asia/Jakarta and writes aging as a string" do
      freeze_time(Time.utc(2026, 5, 10, 12, 0, 0)) do
        create_case!(
          opened_at: Time.utc(2026, 1, 1, 18, 30), # 2026-01-02 01:30 Jakarta
          status: "Closed",
          close_reason: "Duplicate",
          closed_at: Time.utc(2026, 1, 2, 20, 0) # 2026-01-03 03:00 Jakarta
        )

        get "/atcp/cases/export", params: { status: "Closed" }

        row = data_rows.first
        expect(row[1]).to eq("2026-01-02")
        expect(row[2]).to eq("2026-01-03")
        # closed_at is 1.5 days after opened_at, floored to 1 day.
        expect(row[14]).to eq("1")
      end
    end

    it "uses the export date, not the filters, in the filename" do
      create_case!

      freeze_time(Time.utc(2026, 3, 4, 20, 0, 0)) do
        get "/atcp/cases/export", params: { date_from: "2020-01-01" }

        expect(response.headers["Content-Disposition"]).to include(
          "atcp-cases-export-2026-03-05.xlsx"
        )
      end
    end

    it "writes a value starting with = as a plain string, not a formula" do
      create_case!(title: "=1+1")
      get "/atcp/cases/export"

      expect(data_rows.first[3]).to eq("=1+1")
      expect(xlsx_sheet.xpath("//*[local-name()='f']")).to be_empty
    end

    it "truncates text at 32,000 characters with an ellipsis" do
      long_text = "x" * 33_000
      create_case!(root_cause_summary: long_text)
      get "/atcp/cases/export"

      value = data_rows.first[12]
      expect(value.length).to eq(32_001)
      expect(value).to eq("#{"x" * 32_000}…")
    end
  end

  describe "products" do
    before { sign_in(internal_user) }

    it "joins multiple products with '; ' and avoids duplicate SKU labels" do
      atcp_case = create_case!
      add_product!(atcp_case, name: "Axioo P15", sku: "AXIOO-P15")
      add_product!(atcp_case, name: "Axioo P16 AXIOO-P16", sku: "AXIOO-P16")

      get "/atcp/cases/export"

      expect(data_rows.first[6]).to eq(
        "Axioo P15 (AXIOO-P15); Axioo P16 AXIOO-P16"
      )
    end

    it "exports every product of a case even when filtering by one product" do
      atcp_case = create_case!
      first = add_product!(atcp_case, name: "Axioo P15", sku: "AXIOO-P15")
      add_product!(atcp_case, name: "Axioo P16", sku: "AXIOO-P16")

      get "/atcp/cases/export", params: { product_id: first.id }

      expect(data_rows.size).to eq(1)
      expect(data_rows.first[6]).to eq(
        "Axioo P15 (AXIOO-P15); Axioo P16 (AXIOO-P16)"
      )
    end
  end

  describe "filters" do
    before { sign_in(internal_user) }

    it "exports active cases by default and honors the status filter" do
      open_case = create_case!(title: "Still open")
      closed_case =
        create_case!(
          title: "Already closed",
          status: "Closed",
          close_reason: "Duplicate",
          closed_at: 1.hour.ago
        )

      get "/atcp/cases/export"
      expect(exported_case_numbers).to eq([open_case.case_number])

      get "/atcp/cases/export", params: { status: "Closed" }
      expect(exported_case_numbers).to eq([closed_case.case_number])
    end

    it "applies case type, assignee, search, and date filters" do
      pic = Fabricate(:user, username: "filter_pic")
      matching =
        create_case!(
          title: "Battery drains",
          case_type: "Performance",
          assignee: pic,
          opened_at: Time.utc(2026, 2, 10, 5, 0)
        )
      create_case!(
        title: "Another case",
        case_type: "Performance",
        assignee: pic,
        opened_at: Time.utc(2026, 3, 10, 5, 0)
      )
      create_case!(
        title: "Other type",
        case_type: "Other",
        assignee: pic,
        opened_at: Time.utc(2026, 2, 10, 5, 0)
      )

      get "/atcp/cases/export",
          params: {
            case_type: "Performance",
            assignee_id: pic.id,
            q: "Battery",
            date_from: "2026-02-01",
            date_to: "2026-02-28"
          }

      expect(exported_case_numbers).to eq([matching.case_number])
    end

    it "rejects an invalid status once without double rendering" do
      create_case!

      get "/atcp/cases/export", params: { status: "Bogus" }

      expect(response.status).to eq(422)
      expect(response.parsed_body["errors"]).to include(
        I18n.t("atcp_case.errors.invalid_status")
      )
    end

    it "rejects an invalid product filter" do
      get "/atcp/cases/export", params: { product_id: "abc" }

      expect(response.status).to eq(422)
      expect(response.parsed_body["errors"]).to include(
        I18n.t("atcp_case.errors.invalid_filter")
      )
    end

    it "rejects an invalid date filter" do
      get "/atcp/cases/export", params: { date_from: "not-a-date" }

      expect(response.status).to eq(422)
      expect(response.parsed_body["errors"]).to include(
        I18n.t("atcp_case.errors.date_invalid")
      )
    end
  end

  describe "row limit" do
    before { sign_in(internal_user) }

    it "declares the production limit as 5,000 cases" do
      expect(AtcpCaseExcelExport::MAX_ROWS).to eq(5_000)
    end

    it "allows an export that is exactly at the limit" do
      stub_const(AtcpCaseExcelExport, "MAX_ROWS", 2) do
        2.times { create_case! }

        get "/atcp/cases/export"

        expect(response.status).to eq(200)
        expect(data_rows.size).to eq(2)
      end
    end

    it "rejects an export one row above the limit" do
      stub_const(AtcpCaseExcelExport, "MAX_ROWS", 2) do
        3.times { create_case! }

        get "/atcp/cases/export"

        expect(response.status).to eq(422)
        expect(response.parsed_body["errors"]).to include(
          I18n.t("atcp_case.errors.export_too_many_rows", count: 3, max: 2)
        )
      end
    end
  end

  describe "queries" do
    before { sign_in(internal_user) }

    it "loads case products once with preload instead of per case" do
      3.times do |index|
        atcp_case =
          create_case!(
            assignee: Fabricate(:user, username: "pic_#{SecureRandom.hex(4)}")
          )
        add_product!(atcp_case, name: "Product A", sku: "SKU-A-#{index}")
        add_product!(atcp_case, name: "Product B", sku: "SKU-B-#{index}")
      end

      product_queries = []
      callback =
        lambda do |_name, _started, _finished, _unique_id, payload|
          next if payload[:cached] || payload[:name] == "SCHEMA"
          if payload[:sql].include?("atcp_case_products")
            product_queries << payload[:sql]
          end
        end

      ActiveSupport::Notifications.subscribed(callback, "sql.active_record") do
        get "/atcp/cases/export"
      end

      expect(response.status).to eq(200)
      expect(data_rows.size).to eq(3)
      expect(product_queries.size).to eq(1)
    end
  end
end
