# frozen_string_literal: true

require "caxlsx"

class AtcpCaseExcelExport
  HEADERS = [
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
  ].freeze

  MAX_ROWS = 5_000
  MAX_CELL_LENGTH = 32_000
  ELLIPSIS = "…"
  XLSX_MIME =
    "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"

  def self.build(cases)
    new(cases).to_xlsx
  end

  def initialize(cases)
    @cases = cases
  end

  def to_xlsx
    package = Axlsx::Package.new
    workbook = package.workbook
    workbook.use_shared_strings = true

    workbook.add_worksheet(name: "Cases") do |sheet|
      sheet.add_row(
        HEADERS,
        types: Array.new(HEADERS.size, :string),
        style: header_style(sheet)
      )

      @cases.each do |record|
        sheet.add_row(
          row_values(record),
          types: Array.new(HEADERS.size, :string)
        )
      end
    end

    package.to_stream.string
  end

  private

  def header_style(sheet)
    sheet.styles.add_style(
      b: true,
      alignment: {
        horizontal: :center,
        vertical: :center
      }
    )
  end

  def row_values(record)
    [
      record.case_number,
      format_date(record.opened_at),
      format_date(record.closed_at),
      record.title,
      record.case_type,
      record.status,
      products_label(record),
      record.source,
      user_label(record.created_by),
      user_label(record.assignee),
      "-",
      record.bios_version,
      record.root_cause_summary,
      record.solution,
      AtcpCaseTiming.aging_days(record).to_s
    ].map { |value| cell_text(value) }
  end

  def cell_text(value)
    text = value.to_s.strip
    return "-" if text.empty?
    return text if text.length <= MAX_CELL_LENGTH

    "#{text[0, MAX_CELL_LENGTH]}#{ELLIPSIS}"
  end

  def format_date(value)
    return "-" if value.blank?

    value.in_time_zone(jakarta_zone).strftime("%Y-%m-%d")
  end

  def jakarta_zone
    ActiveSupport::TimeZone[Atcp::CasesController::JAKARTA_ZONE]
  end

  def user_label(user)
    user&.name.presence || user&.username.presence || "-"
  end

  def products_label(record)
    labels =
      record
        .atcp_case_products
        .sort_by(&:id)
        .map do |product|
          AtcpCaseProductLabel.label(product.product_name, product.sku_code)
        end
        .reject(&:blank?)

    labels.presence&.join("; ") || "-"
  end
end
