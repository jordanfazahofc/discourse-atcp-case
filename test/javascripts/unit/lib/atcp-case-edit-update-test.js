import { module, test } from "qunit";
import { MAX_UPDATE_TYPE_LENGTH } from "discourse/plugins/discourse-atcp-case/discourse/lib/atcp-case-add-update";
import {
  buildEditUpdatePayload,
  validateEditUpdateType,
} from "discourse/plugins/discourse-atcp-case/discourse/lib/atcp-case-edit-update";

module("Unit | Lib | atcp-case-edit-update", function () {
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

  test("builds only a body payload in body-only mode", function (assert) {
    const initialUpdate = {
      update_type: null,
      body: "Original system note",
    };

    assert.deepEqual(
      buildEditUpdatePayload({
        initialUpdate,
        body: " Updated system note ",
        bodyOnly: true,
        uploadIds: [10],
        removeAttachmentIds: [4],
      }),
      { body: "Updated system note" }
    );

    assert.deepEqual(
      buildEditUpdatePayload({
        initialUpdate,
        updateType: "Ignored type",
        body: "Original system note",
        bodyOnly: true,
      }),
      {}
    );
  });

  test("includes attachment changes in the payload", function (assert) {
    const initialUpdate = {
      update_type: "Vendor communication",
      body: "Original note",
    };

    assert.deepEqual(
      buildEditUpdatePayload({
        initialUpdate,
        updateType: "Vendor communication",
        body: "Original note",
        uploadIds: [10, 11],
      }),
      { upload_ids: [10, 11] }
    );

    assert.deepEqual(
      buildEditUpdatePayload({
        initialUpdate,
        updateType: "Vendor communication",
        body: "Original note",
        removeAttachmentIds: [4],
      }),
      { remove_attachment_ids: [4] }
    );

    assert.deepEqual(
      buildEditUpdatePayload({
        initialUpdate,
        updateType: "Internal note",
        body: "Revised note",
        uploadIds: [10],
        removeAttachmentIds: [4],
      }),
      {
        update_type: "Internal note",
        body: "Revised note",
        upload_ids: [10],
        remove_attachment_ids: [4],
      }
    );
  });

  test("does not fall back to a default when the type is cleared", function (assert) {
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
