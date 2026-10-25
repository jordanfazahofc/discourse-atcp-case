import { module, test } from "qunit";
import {
  MAX_UPDATE_TYPE_LENGTH,
  updateTypeSuggestions,
} from "discourse/plugins/discourse-atcp-case/discourse/lib/atcp-case-add-update";
import {
  buildEditUpdatePayload,
  validateEditUpdateType,
} from "discourse/plugins/discourse-atcp-case/discourse/lib/atcp-case-edit-update";

module("Unit | Lib | atcp-case-edit-update", function () {
  test("uses configured update type suggestions without duplicates", function (assert) {
    assert.deepEqual(
      updateTypeSuggestions({
        update_labels: [" Vendor communication ", "Vendor communication", ""],
      }),
      ["Vendor communication"]
    );

    assert.deepEqual(updateTypeSuggestions({ update_labels: [] }), [
      "General note",
    ]);
  });

  test("requires a non-blank update type", function (assert) {
    assert.deepEqual(validateEditUpdateType(""), { key: "required" });
    assert.deepEqual(validateEditUpdateType("   "), { key: "required" });
    assert.deepEqual(validateEditUpdateType(null), { key: "required" });
  });

  test("accepts trimmed update types up to the maximum length", function (assert) {
    assert.strictEqual(
      validateEditUpdateType(`  ${"x".repeat(MAX_UPDATE_TYPE_LENGTH)}  `),
      null
    );
    assert.deepEqual(
      validateEditUpdateType("x".repeat(MAX_UPDATE_TYPE_LENGTH + 1)),
      { key: "too_long", max: MAX_UPDATE_TYPE_LENGTH }
    );
  });

  test("builds a payload with only changed fields", function (assert) {
    const initialUpdate = {
      update_type: "Vendor communication",
      body: "Original note",
    };

    assert.deepEqual(
      buildEditUpdatePayload({
        initialUpdate,
        updateType: " Vendor communication ",
        body: "  Original note  ",
      }),
      {}
    );

    assert.deepEqual(
      buildEditUpdatePayload({
        initialUpdate,
        updateType: "Internal note",
        body: "Revised note",
      }),
      { update_type: "Internal note", body: "Revised note" }
    );

    assert.deepEqual(
      buildEditUpdatePayload({
        initialUpdate,
        updateType: "Vendor communication",
        body: "Revised note",
      }),
      { body: "Revised note" }
    );

    assert.deepEqual(
      buildEditUpdatePayload({
        initialUpdate,
        updateType: "Internal note",
        body: "Original note",
      }),
      { update_type: "Internal note" }
    );
  });

  test("does not fall back to General note when the type is cleared", function (assert) {
    assert.deepEqual(
      buildEditUpdatePayload({
        initialUpdate: { update_type: "Vendor communication", body: "Note" },
        updateType: "   ",
        body: "Note",
      }),
      { update_type: "" }
    );
  });
});
