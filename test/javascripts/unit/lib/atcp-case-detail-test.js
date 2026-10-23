import { setupTest } from "ember-qunit";
import { module, test } from "qunit";
import {
  caseProductLabel,
  caseReporterLabel,
  collectCaseAttachments,
  displayUserName,
  formatCaseDate,
  formatCaseDateTime,
  hasResolutionContent,
  normalizeCaseDetailTab,
  productLabel,
  systemEventText,
} from "discourse/plugins/discourse-atcp-case/discourse/lib/atcp-case-detail";

module("Unit | Lib | atcp-case-detail", function (hooks) {
  setupTest(hooks);

  test("normalizes detail tab query params", function (assert) {
    assert.strictEqual(normalizeCaseDetailTab(undefined), "progress");
    assert.strictEqual(normalizeCaseDetailTab(""), "progress");
    assert.strictEqual(normalizeCaseDetailTab("bogus"), "progress");
    assert.strictEqual(normalizeCaseDetailTab("technical"), "technical");
    assert.strictEqual(normalizeCaseDetailTab(" ATTACHMENTS "), "attachments");
  });

  test("formats dates and rejects invalid values", function (assert) {
    assert.strictEqual(formatCaseDate("2026-07-10T12:00:00"), "10 Jul 2026");
    assert.strictEqual(
      formatCaseDateTime("2026-07-10T12:30:00"),
      "10 Jul 2026, 12:30"
    );
    assert.strictEqual(formatCaseDate(null), "-");
    assert.strictEqual(formatCaseDateTime("not-a-date"), "-");
  });

  test("builds product labels without repeating the SKU", function (assert) {
    assert.strictEqual(
      productLabel("PRO L7 (NBAX22X)", "NBAX22X"),
      "PRO L7 (NBAX22X)",
      "returns the name when it already contains the SKU"
    );
    assert.strictEqual(
      productLabel("PRO L7", "NBAX22X"),
      "PRO L7 (NBAX22X)",
      "appends a missing SKU"
    );
    assert.strictEqual(
      productLabel("PRO L7", ""),
      "PRO L7",
      "ignores an empty SKU"
    );
    assert.strictEqual(
      productLabel("PRO L7", undefined),
      "PRO L7",
      "ignores an undefined SKU"
    );
    assert.strictEqual(
      productLabel("PRO L7 (nbax22x)", "NBAX22X"),
      "PRO L7 (nbax22x)",
      "compares the SKU case-insensitively"
    );
    assert.strictEqual(
      productLabel("PRO L7 (NBAX22X)", "NBAX22"),
      "PRO L7 (NBAX22X)",
      "returns the name when it contains part of the SKU"
    );
    assert.strictEqual(
      productLabel("PRO L7", "  NBAX22X  "),
      "PRO L7 (NBAX22X)",
      "trims the SKU before appending it"
    );
  });

  test("builds product, reporter, and user labels", function (assert) {
    assert.strictEqual(
      caseProductLabel({ id: 1, name: "Axioo P15", sku: "AXIOO-P15" }),
      "Axioo P15 (AXIOO-P15)"
    );
    assert.strictEqual(
      caseProductLabel({ id: null, name: "Legacy Axioo", sku: null }),
      "Legacy Axioo",
      "deleted products use the snapshot name only"
    );
    assert.strictEqual(
      caseReporterLabel({
        reporter_name: "Budi",
        reporter_branch_name: "Jakarta",
      }),
      "Budi · Jakarta"
    );
    assert.strictEqual(caseReporterLabel({}), "-");
    assert.strictEqual(displayUserName({ name: "Jordan" }), "Jordan");
    assert.strictEqual(displayUserName({ username: "jordan" }), "jordan");
    assert.strictEqual(displayUserName(null), "-");
  });

  test("detects resolution content", function (assert) {
    assert.true(hasResolutionContent({ status: "Closed" }));
    assert.true(hasResolutionContent({ status: "Open", solution: "Update EC" }));
    assert.false(hasResolutionContent({ status: "Open", solution: "  " }));
  });

  test("localizes every system event and falls back safely", function (assert) {
    assert.strictEqual(
      systemEventText({
        system_event: "status_changed",
        from_value: "Open",
        to_value: "Closed",
      }),
      "Status changed from Open to Closed"
    );
    assert.strictEqual(
      systemEventText({
        system_event: "severity_changed",
        from_value: "High",
        to_value: "Critical",
      }),
      "Severity changed from High to Critical"
    );
    assert.strictEqual(
      systemEventText({
        system_event: "assignee_changed",
        from_value: "Unassigned",
        to_value: "Jordan",
      }),
      "Assignee changed from Unassigned to Jordan"
    );
    assert.strictEqual(
      systemEventText({
        system_event: "closed",
        details: { close_reason: "Resolved" },
      }),
      "Case closed (Resolved)"
    );
    assert.strictEqual(
      systemEventText({ system_event: "reopened" }),
      "Case reopened"
    );
    assert.strictEqual(
      systemEventText({
        system_event: "future_event",
        from_value: "A",
        to_value: "B",
      }),
      "A → B"
    );
  });

  test("collects attachments in timeline order with parent metadata", function (assert) {
    const rows = collectCaseAttachments([
      {
        id: 2,
        update_type: "Investigation",
        created_at: "2026-07-14T08:00:00Z",
        user: { name: "Jordan" },
        attachments: [
          { upload_id: 12, original_filename: "new.pdf" },
          { upload_id: 11, original_filename: "old.png" },
        ],
      },
      {
        id: 1,
        update_type: null,
        created_at: "2026-07-13T08:00:00Z",
        user: { username: "jordan" },
        attachments: [{ upload_id: 10, original_filename: "first.pdf" }],
      },
    ]);

    assert.deepEqual(
      rows.map((row) => row.original_filename),
      ["new.pdf", "old.png", "first.pdf"]
    );
    assert.strictEqual(rows[0].update_id, 2);
    assert.strictEqual(rows[0].uploaded_by, "Jordan");
    assert.strictEqual(rows[2].uploaded_by, "jordan");
  });
});
