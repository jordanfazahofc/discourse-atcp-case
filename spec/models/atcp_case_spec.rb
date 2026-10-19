# frozen_string_literal: true

RSpec.describe AtcpCase do
  def case_attrs(**overrides)
    {
      title: "Device does not boot",
      case_type: "Hardware defect",
      severity: "Medium",
      status: "Open",
      source: "manual",
      symptom: "Boot loop after updating BIOS",
      created_by: Fabricate(:user)
    }.merge(overrides)
  end

  describe "validations" do
    it "accepts every configured case type" do
      AtcpCase::CASE_TYPES.each do |case_type|
        expect(Fabricate.build(:atcp_case, case_type: case_type)).to be_valid
      end
    end

    it "rejects a case type outside the configured list" do
      record = Fabricate.build(:atcp_case, case_type: "Unknown")
      expect(record).to be_invalid
      expect(record.errors[:case_type]).to be_present
    end

    it "rejects a severity outside the configured list" do
      record = Fabricate.build(:atcp_case, severity: "Urgent")
      expect(record).to be_invalid
      expect(record.errors[:severity]).to be_present
    end

    it "allows frequency and reproducibility to be empty" do
      record = Fabricate.build(:atcp_case, frequency: nil, reproducibility: nil)
      expect(record).to be_valid
    end

    it "limits source to 255 characters" do
      expect(Fabricate.build(:atcp_case, source: "a" * 255)).to be_valid
      expect(Fabricate.build(:atcp_case, source: "a" * 256)).to be_invalid
    end

    it "defaults opened_at when blank" do
      record = Fabricate.build(:atcp_case, opened_at: nil)
      record.validate
      expect(record.opened_at).to be_present
    end
  end

  describe "close rules" do
    it "requires a close reason when status is Closed" do
      record = Fabricate.build(:atcp_case, status: "Closed", close_reason: nil)
      expect(record).to be_invalid
      expect(record.errors[:close_reason]).to be_present
    end

    it "requires a solution when closed as Resolved" do
      record =
        Fabricate.build(
          :atcp_case,
          status: "Closed",
          close_reason: "Resolved",
          solution: nil
        )
      expect(record).to be_invalid
      expect(record.errors[:solution]).to be_present
    end

    it "accepts a Resolved close with a solution" do
      record =
        Fabricate.build(
          :atcp_case,
          status: "Closed",
          close_reason: "Resolved",
          solution: "Replace the SSD"
        )
      expect(record).to be_valid
    end

    it "accepts other close reasons without a solution" do
      record =
        Fabricate.build(:atcp_case, status: "Closed", close_reason: "Duplicate")
      expect(record).to be_valid
    end

    it "allows Open to move directly to Closed" do
      record = Fabricate(:atcp_case)
      record.update!(status: "Closed", close_reason: "Cancelled")
      expect(record.reload.status).to eq("Closed")
    end
  end

  describe ".next_case_number" do
    it "starts at CASE-<year>-0001" do
      freeze_time(Time.utc(2026, 5, 1)) do
        expect(AtcpCase.next_case_number).to eq("CASE-2026-0001")
      end
    end

    it "increments from the highest number of the current year" do
      freeze_time(Time.utc(2026, 5, 1)) do
        Fabricate(:atcp_case, case_number: "CASE-2026-0007")
        expect(AtcpCase.next_case_number).to eq("CASE-2026-0008")
      end
    end

    it "resets the counter for a new year" do
      freeze_time(Time.utc(2025, 12, 31)) do
        Fabricate(:atcp_case, case_number: "CASE-2025-0042")
      end

      freeze_time(Time.utc(2026, 1, 2)) do
        expect(AtcpCase.next_case_number).to eq("CASE-2026-0001")
      end
    end

    it "uses the Jakarta calendar year for the number" do
      freeze_time(Time.utc(2025, 12, 31, 18, 0)) do
        expect(AtcpCase.next_case_number).to eq("CASE-2026-0001")
      end

      freeze_time(Time.utc(2025, 12, 31, 16, 0)) do
        expect(AtcpCase.next_case_number).to eq("CASE-2025-0001")
      end
    end
  end

  describe ".create_with_generated_number!" do
    it "assigns the generated number" do
      freeze_time(Time.utc(2026, 5, 1)) do
        record = AtcpCase.create_with_generated_number!(case_attrs)

        expect(record).to be_persisted
        expect(record.case_number).to eq("CASE-2026-0001")
      end
    end

    it "retries with a fresh number on collision" do
      freeze_time(Time.utc(2026, 5, 1)) do
        Fabricate(:atcp_case, case_number: "CASE-2026-0001")
        AtcpCase.stubs(:next_case_number).returns(
          "CASE-2026-0001",
          "CASE-2026-0002"
        )

        record = AtcpCase.create_with_generated_number!(case_attrs)

        expect(record.case_number).to eq("CASE-2026-0002")
      end
    end

    it "raises when every attempt collides" do
      freeze_time(Time.utc(2026, 5, 1)) do
        Fabricate(:atcp_case, case_number: "CASE-2026-0001")
        AtcpCase.stubs(:next_case_number).returns("CASE-2026-0001")

        expect {
          AtcpCase.create_with_generated_number!(case_attrs)
        }.to raise_error(ActiveRecord::RecordNotUnique)
      end
    end

    it "succeeds inside an outer transaction when the first number collides" do
      freeze_time(Time.utc(2026, 5, 1)) do
        Fabricate(:atcp_case, case_number: "CASE-2026-0001")
        AtcpCase.stubs(:next_case_number).returns(
          "CASE-2026-0001",
          "CASE-2026-0002"
        )

        created = nil
        AtcpCase.transaction do
          created = AtcpCase.create_with_generated_number!(case_attrs)
        end

        expect(created).to be_persisted
        expect(created.case_number).to eq("CASE-2026-0002")
      end
    end
  end
end
