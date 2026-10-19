# frozen_string_literal: true

require_relative "../../lib/atcp_case_upload_patch"
require_relative "../../lib/atcp_case_upload_validator_patch"

RSpec.describe "Atcp case attachment upload" do
  fab!(:internal_group, :group)
  fab!(:internal_user, :user)
  fab!(:outsider, :user)
  fab!(:admin)

  before do
    internal_group.add(internal_user)
    SiteSetting.atcp_internal_groups = internal_group.id.to_s
    SiteSetting.atcp_case_max_attachment_mb = 100
    ensure_case_upload_patches!
  end

  def ensure_case_upload_patches!
    if UploadCreator.ancestors.exclude?(Atcp::CaseUploadPatch)
      UploadCreator.prepend(Atcp::CaseUploadPatch)
    end
    if UploadValidator.ancestors.exclude?(Atcp::CaseUploadValidatorPatch)
      UploadValidator.prepend(Atcp::CaseUploadValidatorPatch)
    end
  end

  def upload_file(name, bytes: nil)
    path = File.join(Dir.mktmpdir, name)
    File.binwrite(path, bytes || SecureRandom.hex(16))
    Rack::Test::UploadedFile.new(
      path,
      "application/octet-stream",
      false,
      original_filename: name
    )
  end

  context "when signed in as an internal member" do
    before { sign_in(internal_user) }

    it "accepts every extension configured for case attachments" do
      %w[7z mp4 xls zip rar pdf].each do |extension|
        post "/uploads.json",
             params: {
               file: upload_file("case.#{extension}"),
               upload_type: "atcp-case-attachment"
             }

        expect(response.status).to eq(200),
        "expected .#{extension} to be accepted, got #{response.status}: #{response.parsed_body}"
        expect(response.parsed_body["url"]).to be_present
      end
    end

    it "accepts small png, jpg, and webp images and persists the uploads" do
      %w[logo.png logo.jpg animated.webp].each do |fixture|
        post "/uploads.json",
             params: {
               file: Rack::Test::UploadedFile.new(file_from_fixtures(fixture)),
               upload_type: "atcp-case-attachment"
             }

        expect(response.status).to eq(200),
        "expected #{fixture} to be accepted, got #{response.status}: #{response.parsed_body}"

        upload = Upload.find_by(id: response.parsed_body["id"])
        expect(upload).to be_present
        expect(upload.original_filename).to end_with(fixture)
      end
    end

    it "rejects extensions outside the case allowlist" do
      %w[exe sh].each do |extension|
        post "/uploads.json",
             params: {
               file: upload_file("case.#{extension}"),
               upload_type: "atcp-case-attachment"
             }

        expect(response.status).to eq(422)
        expect(response.parsed_body["errors"].first).to include(
          "not authorized"
        )
        expect(response.parsed_body["errors"].first).to include("7z")
      end
    end

    it "does not leak case extensions to regular upload types" do
      post "/uploads.json",
           params: {
             file: upload_file("notes.7z"),
             upload_type: "composer"
           }

      expect(response.status).to eq(422)
      expect(response.parsed_body["errors"].first).to include("not authorized")
    end

    it "applies atcp_case_max_attachment_mb instead of the global attachment limit" do
      SiteSetting.max_attachment_size_kb = 10_240
      SiteSetting.atcp_case_max_attachment_mb = 100

      post "/uploads.json",
           params: {
             file: upload_file("big.zip", bytes: "A" * 11.megabytes),
             upload_type: "atcp-case-attachment"
           }

      expect(response.status).to eq(200)
      expect(response.parsed_body["url"]).to be_present
    end

    it "rejects files larger than atcp_case_max_attachment_mb" do
      SiteSetting.atcp_case_max_attachment_mb = 1

      post "/uploads.json",
           params: {
             file: upload_file("big.zip", bytes: "A" * 2.megabytes),
             upload_type: "atcp-case-attachment"
           }

      expect(response.status).to eq(422)
      expect(response.parsed_body["errors"].first).to eq(
        I18n.t("upload.attachments.too_large_humanized", max_size: "1 MB")
      )
    end

    it "still applies the global attachment limit to regular uploads" do
      SiteSetting.authorized_extensions = "zip"
      SiteSetting.max_attachment_size_kb = 10_240
      SiteSetting.atcp_case_max_attachment_mb = 100

      post "/uploads.json",
           params: {
             file: upload_file("big.zip", bytes: "A" * 11.megabytes),
             upload_type: "composer"
           }

      expect(response.status).to eq(422)
      expect(response.parsed_body["errors"].first).to eq(
        I18n.t("upload.attachments.too_large_humanized", max_size: "10 MB")
      )
    end
  end

  context "when signed in as a non-internal user" do
    before { sign_in(outsider) }

    it "rejects case attachments and keeps the default rules" do
      post "/uploads.json",
           params: {
             file: upload_file("case.7z"),
             upload_type: "atcp-case-attachment"
           }

      expect(response.status).to eq(422)
      expect(response.parsed_body["errors"].first).to include("not authorized")
    end

    it "accepts png via default rules but applies the global size limit (case flag stays inactive)" do
      SiteSetting.atcp_case_max_attachment_mb = 100
      SiteSetting.max_image_size_kb = 1

      post "/uploads.json",
           params: {
             file: Rack::Test::UploadedFile.new(file_from_fixtures("logo.png")),
             upload_type: "atcp-case-attachment"
           }

      expect(response.status).to eq(422)
      expect(response.parsed_body["errors"].first).to eq(
        I18n.t("upload.images.too_large_humanized", max_size: "1 KB")
      )

      SiteSetting.max_image_size_kb = 10_240

      post "/uploads.json",
           params: {
             file: Rack::Test::UploadedFile.new(file_from_fixtures("logo.png")),
             upload_type: "atcp-case-attachment"
           }

      expect(response.status).to eq(200)
      expect(Upload.find_by(id: response.parsed_body["id"])).to be_present
      expect(Thread.current[:atcp_case_upload]).to be_nil
    end
  end

  context "when signed in as an admin" do
    before { sign_in(admin) }

    it "accepts case attachments through the internal gate" do
      post "/uploads.json",
           params: {
             file: upload_file("case.7z"),
             upload_type: "atcp-case-attachment"
           }

      expect(response.status).to eq(200)
      expect(response.parsed_body["url"]).to be_present
    end
  end
end
