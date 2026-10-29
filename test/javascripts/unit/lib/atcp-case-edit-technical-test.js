import { module, test } from "qunit";
import {
  buildEditTechnicalPayload,
  TECHNICAL_FIELDS,
} from "discourse/plugins/discourse-atcp-case/discourse/lib/atcp-case-edit-technical";

const ATCP_CASE = {
  symptom: "Fan noise on boot",
  frequency: "Always",
  reproducibility: "Reproducible",
  non_trigger_conditions: null,
  bios_version: "1.2.3",
  os_driver_info: "Windows 11",
};

module("Unit | Lib | atcp-case-edit-technical", function () {
  test("lists the technical fields in display order", function (assert) {
    assert.deepEqual(TECHNICAL_FIELDS, [
      "symptom",
      "frequency",
      "reproducibility",
      "non_trigger_conditions",
      "bios_version",
      "os_driver_info",
    ]);
  });

  test("builds a payload with only changed fields", function (assert) {
    assert.deepEqual(
      buildEditTechnicalPayload({
        atcpCase: ATCP_CASE,
        data: { ...ATCP_CASE },
      }),
      {}
    );

    assert.deepEqual(
      buildEditTechnicalPayload({
        atcpCase: ATCP_CASE,
        data: { ...ATCP_CASE, symptom: "Updated symptom" },
      }),
      { symptom: "Updated symptom" }
    );

    assert.deepEqual(
      buildEditTechnicalPayload({
        atcpCase: ATCP_CASE,
        data: {
          ...ATCP_CASE,
          frequency: "Intermittent",
          bios_version: "2.0.0",
        },
      }),
      { frequency: "Intermittent", bios_version: "2.0.0" }
    );
  });

  test("treats missing and blank values as unchanged", function (assert) {
    assert.deepEqual(
      buildEditTechnicalPayload({
        atcpCase: ATCP_CASE,
        data: {
          ...ATCP_CASE,
          non_trigger_conditions: "",
          os_driver_info: "  Windows 11  ",
        },
      }),
      {}
    );

    assert.deepEqual(
      buildEditTechnicalPayload({
        atcpCase: { ...ATCP_CASE, frequency: "  " },
        data: { ...ATCP_CASE, frequency: "" },
      }),
      {}
    );
  });

  test("sends an empty string when a value is cleared", function (assert) {
    assert.deepEqual(
      buildEditTechnicalPayload({
        atcpCase: ATCP_CASE,
        data: { ...ATCP_CASE, frequency: "" },
      }),
      { frequency: "" }
    );

    assert.deepEqual(
      buildEditTechnicalPayload({
        atcpCase: { ...ATCP_CASE, non_trigger_conditions: "Only on cold boot" },
        data: { ...ATCP_CASE, non_trigger_conditions: "   " },
      }),
      { non_trigger_conditions: "" }
    );
  });
});
