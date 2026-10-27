import { module, test } from "qunit";
import { MAX_ATTACHMENTS } from "discourse/plugins/discourse-atcp-case/discourse/lib/atcp-case-add-update";
import {
  exceedsAttachmentLimit,
  remainingAttachmentCount,
  totalAttachmentCount,
} from "discourse/plugins/discourse-atcp-case/discourse/lib/atcp-case-attachments";

module("Unit | Lib | atcp-case-attachments", function () {
  const existingAttachments = [{ id: 1 }, { id: 2 }, { id: 3 }];

  test("counts remaining existing attachments", function (assert) {
    assert.strictEqual(remainingAttachmentCount(existingAttachments), 3);
    assert.strictEqual(
      remainingAttachmentCount(existingAttachments, [1, 3]),
      1
    );
    assert.strictEqual(
      remainingAttachmentCount(existingAttachments, [99]),
      3,
      "ignores ids that are not present"
    );
  });

  test("counts existing and new attachments together", function (assert) {
    assert.strictEqual(
      totalAttachmentCount({
        existingAttachments,
        removeAttachmentIds: [2],
        uploadIds: [10, 11],
      }),
      4
    );
  });

  test("detects the attachment limit", function (assert) {
    const existing = Array.from({ length: MAX_ATTACHMENTS }, (_, index) => ({
      id: index + 1,
    }));

    assert.false(
      exceedsAttachmentLimit({ existingAttachments: existing }),
      "exactly the limit is allowed"
    );
    assert.true(
      exceedsAttachmentLimit({
        existingAttachments: existing,
        uploadIds: [99],
      })
    );
    assert.false(
      exceedsAttachmentLimit({
        existingAttachments: existing,
        removeAttachmentIds: [1],
        uploadIds: [99],
      })
    );
  });
});
