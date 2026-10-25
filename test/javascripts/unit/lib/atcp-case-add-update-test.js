import { module, test } from "qunit";
import {
  addUpdateStatusOptions,
  attachmentValidation,
  buildAddUpdatePayload,
  hasAttachmentCapacity,
  isDuplicateFile,
  MAX_ATTACHMENTS,
  MAX_UPDATE_TYPE_LENGTH,
  normalizeUpdateType,
  normalizeUploadFileName,
  resolveUploadCompletion,
  updateTypeValidation,
} from "discourse/plugins/discourse-atcp-case/discourse/lib/atcp-case-add-update";

module("Unit | Lib | atcp-case-add-update", function () {
  test("validates attachment extensions case-insensitively", function (assert) {
    const options = { extensions: ["PDF", ".png"], max_mb: 100 };

    assert.strictEqual(
      attachmentValidation({ name: "report.pdf", size: 10 }, options),
      null
    );
    assert.strictEqual(
      attachmentValidation({ name: "photo.PNG", size: 10 }, options),
      null
    );
    assert.deepEqual(
      attachmentValidation({ name: "archive.zip", size: 10 }, options),
      { key: "file_type" }
    );
    assert.deepEqual(
      attachmentValidation({ name: "no-extension", size: 10 }, options),
      { key: "file_type" }
    );
  });

  test("allows any extension when no allow-list is configured", function (assert) {
    assert.strictEqual(
      attachmentValidation(
        { name: "archive.zip", size: 10 },
        { extensions: [], max_mb: 100 }
      ),
      null
    );
  });

  test("validates attachment size using the configured MB limit", function (assert) {
    const options = { extensions: ["pdf"], max_mb: 2 };

    assert.strictEqual(
      attachmentValidation(
        { name: "report.pdf", size: 2 * 1024 * 1024 },
        options
      ),
      null
    );
    assert.deepEqual(
      attachmentValidation(
        { name: "report.pdf", size: 2 * 1024 * 1024 + 1 },
        options
      ),
      { key: "file_size", maxMb: 2 }
    );
  });

  test("uses safe size defaults for invalid settings", function (assert) {
    assert.deepEqual(
      attachmentValidation(
        { name: "report.pdf", size: 101 * 1024 * 1024 },
        { extensions: ["pdf"], max_mb: "invalid" }
      ),
      { key: "file_size", maxMb: 100 }
    );
  });

  test("detects duplicate file names case-insensitively", function (assert) {
    const files = [{ name: "Report.PDF" }, { name: "photo.png" }];

    assert.true(isDuplicateFile({ name: " report.pdf " }, files));
    assert.true(isDuplicateFile({ name: "PHOTO.PNG" }, files));
    assert.false(isDuplicateFile({ name: "other.pdf" }, files));
  });

  test("normalizes an optional update type", function (assert) {
    assert.strictEqual(normalizeUpdateType("  Vendor call  "), "Vendor call");
    assert.strictEqual(normalizeUpdateType(""), "General note");
    assert.strictEqual(normalizeUpdateType("   "), "General note");
    assert.strictEqual(normalizeUpdateType(null), "General note");
  });

  test("accepts update types up to 100 characters", function (assert) {
    assert.strictEqual(
      updateTypeValidation("x".repeat(MAX_UPDATE_TYPE_LENGTH)),
      null
    );
    assert.deepEqual(
      updateTypeValidation(`  ${"x".repeat(MAX_UPDATE_TYPE_LENGTH + 1)}  `),
      { key: "too_long", max: MAX_UPDATE_TYPE_LENGTH }
    );
  });

  test("normalizes upload file names for matching", function (assert) {
    assert.strictEqual(
      normalizeUploadFileName("  Diagnostic.PDF  "),
      "diagnostic.pdf"
    );
    assert.strictEqual(normalizeUploadFileName(null), "");
  });

  test("matches upload completions by normalized file name", function (assert) {
    const files = [
      { name: "Report.PDF", status: "uploading" },
      { name: "photo.png", status: "uploading" },
    ];

    const result = resolveUploadCompletion(files, {
      original_filename: " report.pdf ",
    });

    assert.deepEqual(result.matched, [files[0]]);
    assert.deepEqual(result.unmatched, []);
  });

  test("falls back to the only uploading file when the name differs", function (assert) {
    const files = [{ name: "report.pdf", status: "uploading" }];

    const result = resolveUploadCompletion(files, {
      original_filename: "normalized-report.pdf",
    });

    assert.deepEqual(result.matched, files);
    assert.deepEqual(result.unmatched, []);
  });

  test("fails every uploading file when the completion cannot be matched", function (assert) {
    const files = [
      { name: "report.pdf", status: "uploading" },
      { name: "photo.png", status: "uploading" },
      { name: "notes.txt", status: "failed" },
    ];

    const result = resolveUploadCompletion(files, {
      original_filename: "unknown.pdf",
    });

    assert.deepEqual(result.matched, []);
    assert.deepEqual(result.unmatched, [files[0], files[1]]);
  });

  test("enforces the attachment limit", function (assert) {
    const files = Array.from({ length: MAX_ATTACHMENTS - 1 }, (_, index) => ({
      name: `file-${index}.pdf`,
    }));

    assert.true(hasAttachmentCapacity(files));
    assert.false(hasAttachmentCapacity([...files, { name: "last.pdf" }]));
  });

  test("excludes the current and closed statuses", function (assert) {
    assert.deepEqual(
      addUpdateStatusOptions(
        ["Open", "In Progress", "On Hold", "Solution Found", "Closed"],
        "In Progress"
      ),
      ["Open", "On Hold", "Solution Found"]
    );
  });

  test("falls back to the standard statuses", function (assert) {
    assert.deepEqual(addUpdateStatusOptions(null, "Open"), [
      "In Progress",
      "On Hold",
      "Solution Found",
    ]);
  });

  test("builds a payload with only provided values", function (assert) {
    assert.deepEqual(
      buildAddUpdatePayload({
        updateType: " General note ",
        body: "  Findings  ",
        status: "In Progress",
        uploadIds: [1, 2],
      }),
      {
        update_type: "General note",
        body: "Findings",
        status: "In Progress",
        upload_ids: [1, 2],
      }
    );

    assert.deepEqual(
      buildAddUpdatePayload({
        updateType: "   ",
        body: "   ",
        status: "",
        uploadIds: [],
      }),
      {
        update_type: "General note",
        upload_ids: [],
      }
    );

    assert.deepEqual(
      buildAddUpdatePayload({
        updateType: "Vendor communication",
        body: "Following up",
        uploadIds: [],
      }),
      {
        update_type: "Vendor communication",
        body: "Following up",
        upload_ids: [],
      }
    );
  });
});
