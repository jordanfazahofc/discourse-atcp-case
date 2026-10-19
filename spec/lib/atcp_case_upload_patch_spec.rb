# frozen_string_literal: true

require_relative "../../lib/atcp_case_upload_patch"
require_relative "../../lib/atcp_case_upload_validator_patch"

RSpec.describe Atcp::CaseUploadPatch do
  fab!(:internal_group, :group)
  fab!(:internal_user, :user)
  fab!(:outsider, :user)

  before do
    if UploadCreator.ancestors.exclude?(Atcp::CaseUploadPatch)
      UploadCreator.prepend(Atcp::CaseUploadPatch)
    end
    if UploadValidator.ancestors.exclude?(Atcp::CaseUploadValidatorPatch)
      UploadValidator.prepend(Atcp::CaseUploadValidatorPatch)
    end

    internal_group.add(internal_user)
    SiteSetting.atcp_internal_groups = internal_group.id.to_s
    Thread.current[:atcp_case_upload] = nil
  end

  after { Thread.current[:atcp_case_upload] = nil }

  def local_file(name, bytes: nil)
    path = File.join(Dir.mktmpdir, name)
    File.binwrite(path, bytes || SecureRandom.hex(16))
    File.open(path)
  end

  it "activates the flag for internal members and clears it after the upload" do
    upload =
      UploadCreator.new(
        local_file("case.7z"),
        "case.7z",
        type: "atcp-case-attachment"
      ).create_for(internal_user.id)

    expect(upload.errors).to be_empty
    expect(upload.persisted?).to eq(true)
    expect(Thread.current[:atcp_case_upload]).to be_nil
  end

  it "does not keep case extensions for a following regular upload on the same thread" do
    accepted =
      UploadCreator.new(
        local_file("case.7z"),
        "case.7z",
        type: "atcp-case-attachment"
      ).create_for(internal_user.id)
    expect(accepted.errors).to be_empty

    rejected =
      UploadCreator.new(
        local_file("notes.7z"),
        "notes.7z",
        type: "composer"
      ).create_for(internal_user.id)

    expect(rejected.errors).to be_present
    expect(Thread.current[:atcp_case_upload]).to be_nil
  end

  it "keeps the flag inactive for non-internal users" do
    upload =
      UploadCreator.new(
        local_file("case.7z"),
        "case.7z",
        type: "atcp-case-attachment"
      ).create_for(outsider.id)

    expect(upload.errors).to be_present
    expect(Thread.current[:atcp_case_upload]).to be_nil
  end

  it "clears the flag even when the upload fails" do
    empty = Tempfile.new(%w[empty .zip])
    empty.close

    upload =
      UploadCreator.new(
        empty,
        "empty.zip",
        type: "atcp-case-attachment"
      ).create_for(internal_user.id)

    expect(upload.errors).not_to be_empty
    expect(Thread.current[:atcp_case_upload]).to be_nil
  end
end
