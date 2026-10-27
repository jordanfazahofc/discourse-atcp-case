import {
  click,
  fillIn,
  render,
  settled,
  triggerKeyEvent,
  waitFor,
} from "@ember/test-helpers";
import { module, test } from "qunit";
import sinon from "sinon";
import { setupRenderingTest } from "discourse/tests/helpers/component-test";
import pretender, {
  parsePostData,
  response,
} from "discourse/tests/helpers/create-pretender";
import { createFile } from "discourse/tests/helpers/qunit-helpers";
import AtcpCaseDetailEditUpdate from "discourse/plugins/discourse-atcp-case/discourse/components/atcp-case/detail/edit-update";
import { openCase } from "../../fixtures/atcp-case-detail";

const FORM_OPTIONS = {
  upload: {
    extensions: ["pdf", "png"],
    max_mb: 2,
  },
};

const UPLOAD_RESPONSE = {
  id: 501,
  url: "/uploads/default/original/1X/diagnostic.pdf",
  short_url: "upload://diagnostic.pdf",
  original_filename: "diagnostic.pdf",
  human_filesize: "12 KB",
  filesize: 12_000,
  extension: "pdf",
};

async function renderEditor(context) {
  await render(
    <template>
      <AtcpCaseDetailEditUpdate
        @update={{context.update}}
        @atcpCase={{context.atcpCase}}
        @bodyOnly={{context.bodyOnly}}
        @formOptions={{context.formOptions}}
        @onSaved={{context.onSaved}}
        @onCancel={{context.onCancel}}
        @onDirtyChange={{context.onDirtyChange}}
      />
    </template>
  );
}

function uploadEventName(context) {
  return `upload-mixin:atcp-case-edit-update-${context.update.id}:add-files`;
}

function uploadCompleteEventName(context) {
  return `upload-mixin:atcp-case-edit-update-${context.update.id}:all-uploads-complete`;
}

module("Integration | Component | AtcpCaseDetailEditUpdate", function (hooks) {
  setupRenderingTest(hooks, { stubRouter: true });

  hooks.beforeEach(function () {
    this.atcpCase = openCase();
    this.update = this.atcpCase.updates[1];
    this.bodyOnly = false;
    this.formOptions = FORM_OPTIONS;
    this.appEvents = this.owner.lookup("service:app-events");
    this.router = this.owner.lookup("service:router");
    this.refreshes = 0;
    this.router.refresh = () => {
      this.refreshes += 1;
      return Promise.resolve();
    };
    this.saved = 0;
    this.onSaved = () => {
      this.saved += 1;
    };
    this.cancelled = 0;
    this.onCancel = () => {
      this.cancelled += 1;
    };
    this.dirtyChanges = [];
    this.onDirtyChange = (dirty) => {
      this.dirtyChanges.push(dirty);
    };
    this.dialog = this.owner.lookup("service:dialog");
    this.a11y = this.owner.lookup("service:a11y");
    this.discard = true;
    this.dialogParams = null;
    this.dialog.confirm = (params) => {
      this.dialogParams = params;
      return Promise.resolve(this.discard);
    };
  });

  test("renders a plain update type field without suggestions", async function (assert) {
    await renderEditor(this);

    assert
      .dom(
        ".atcp-case-detail-edit-update .form-kit__field[data-name='update_type'] input"
      )
      .hasValue("Vendor communication")
      .hasAttribute("maxlength", "100")
      .hasAttribute("placeholder", "Update case")
      .doesNotHaveAttribute("list");
    assert
      .dom(
        ".atcp-case-detail-edit-update .form-kit__field[data-name='update_type'] datalist"
      )
      .doesNotExist();
    assert
      .dom(
        ".atcp-case-detail-edit-update .form-kit__field[data-name='update_type']"
      )
      .includesText("Required.")
      .doesNotIncludeText("suggestion");
    assert
      .dom(
        ".atcp-case-detail-edit-update .form-kit__field[data-name='body'] textarea"
      )
      .hasValue("Uploaded the requested evidence.\nSecond line.");
    assert
      .dom(".atcp-case-detail-edit-update__save")
      .hasText("Save changes")
      .isDisabled("the form has no changes");
  });

  test("sends only the changed fields", async function (assert) {
    let submitted;

    pretender.put("/atcp/cases/1/updates/29.json", (request) => {
      submitted = parsePostData(request.requestBody);
      return response({ update: { ...this.update, edited_at: "now" } });
    });

    await renderEditor(this);
    await fillIn(
      ".atcp-case-detail-edit-update .form-kit__field[data-name='update_type'] input",
      "Internal note"
    );
    await click(".atcp-case-detail-edit-update__save");

    assert.deepEqual(submitted, { update_type: "Internal note" });
    assert.strictEqual(this.refreshes, 1);
    assert.strictEqual(this.saved, 1);
  });

  test("trims the note without sending unchanged fields", async function (assert) {
    let submitted;

    pretender.put("/atcp/cases/1/updates/29.json", (request) => {
      submitted = parsePostData(request.requestBody);
      return response({ update: this.update });
    });

    await renderEditor(this);
    await fillIn(
      ".atcp-case-detail-edit-update .form-kit__field[data-name='body'] textarea",
      "  Revised note  "
    );
    await click(".atcp-case-detail-edit-update__save");

    assert.deepEqual(submitted, { body: "Revised note" });
  });

  test("rejects a blank update type without a request", async function (assert) {
    let requested = false;

    pretender.put("/atcp/cases/1/updates/29.json", () => {
      requested = true;
      return response({});
    });

    await renderEditor(this);
    await fillIn(
      ".atcp-case-detail-edit-update .form-kit__field[data-name='update_type'] input",
      "   "
    );
    await click(".atcp-case-detail-edit-update__save");

    assert.false(requested);
    assert
      .dom(
        ".atcp-case-detail-edit-update .form-kit__field[data-name='update_type'] .form-kit__errors"
      )
      .includesText("Update type is required");
  });

  test("rejects a blank note when no attachments remain", async function (assert) {
    this.update = { ...this.update, attachments: [] };

    await renderEditor(this);
    await fillIn(
      ".atcp-case-detail-edit-update .form-kit__field[data-name='body'] textarea",
      "   "
    );
    await click(".atcp-case-detail-edit-update__save");

    assert
      .dom(
        ".atcp-case-detail-edit-update .form-kit__field[data-name='body'] .form-kit__errors"
      )
      .includesText("Add a note or keep at least one file attached");
  });

  test("shows existing attachments and toggles removal", async function (assert) {
    await renderEditor(this);

    assert
      .dom(".atcp-case-detail-edit-update__existing-file")
      .exists({ count: 2 });
    assert
      .dom(".atcp-case-detail-edit-update__existing-file")
      .includesText("fan-noise.png");
    assert
      .dom(".atcp-case-detail-edit-update__save")
      .isDisabled("no attachment has been marked for removal");

    await click(".atcp-case-detail-edit-update__remove-existing");

    assert
      .dom(".atcp-case-detail-edit-update__existing-file--removed")
      .exists({ count: 1 })
      .includesText("Marked for removal");
    assert
      .dom(".atcp-case-detail-edit-update__undo-remove")
      .hasText("Undo");
    assert
      .dom(".atcp-case-detail-edit-update__save")
      .isNotDisabled("removing an attachment is a change");

    await click(".atcp-case-detail-edit-update__undo-remove");

    assert
      .dom(".atcp-case-detail-edit-update__existing-file--removed")
      .doesNotExist();
    assert
      .dom(".atcp-case-detail-edit-update__save")
      .isDisabled("undoing the removal clears the change");
  });

  test("sends removed attachment ids on save", async function (assert) {
    let submitted;

    pretender.put("/atcp/cases/1/updates/29.json", (request) => {
      submitted = parsePostData(request.requestBody);
      return response({ update: this.update });
    });

    await renderEditor(this);
    await click(".atcp-case-detail-edit-update__remove-existing");
    await click(".atcp-case-detail-edit-update__save");

    assert.deepEqual(submitted, {
      "remove_attachment_ids[]": ["201"],
    });
    assert.strictEqual(this.refreshes, 1);
    assert.strictEqual(this.saved, 1);
  });

  test("adds a new attachment on save", async function (assert) {
    let submitted;

    pretender.post("/uploads.json", () => response(UPLOAD_RESPONSE));
    pretender.put("/atcp/cases/1/updates/29.json", (request) => {
      submitted = parsePostData(request.requestBody);
      return response({ update: this.update });
    });

    await renderEditor(this);

    const uploaded = new Promise((resolve) => {
      this.appEvents.one(uploadCompleteEventName(this), resolve);
    });
    this.appEvents.trigger(
      uploadEventName(this),
      createFile("diagnostic.pdf", "application/pdf")
    );
    await uploaded;
    await settled();

    assert
      .dom(".atcp-case-detail-edit-update__file")
      .includesText("diagnostic.pdf");

    await click(".atcp-case-detail-edit-update__save");

    assert.deepEqual(submitted, {
      "upload_ids[]": ["501"],
    });
  });

  test("confirms before discarding attachment changes", async function (assert) {
    await renderEditor(this);
    await click(".atcp-case-detail-edit-update__remove-existing");

    this.discard = false;
    await click(".atcp-case-detail-edit-update__cancel");

    assert.strictEqual(
      this.dialogParams.message,
      "Discard your changes to this update?"
    );
    assert.strictEqual(this.cancelled, 0, "keeps editing");

    this.discard = true;
    await click(".atcp-case-detail-edit-update__cancel");

    assert.strictEqual(this.cancelled, 1);
  });

  test("shows attachment server errors under the editor", async function (assert) {
    pretender.put("/atcp/cases/1/updates/29.json", () =>
      response(422, {
        errors: {
          remove_attachment_ids: ["Attachment 4 is not part of this update"],
          upload_ids: ["The attachment belongs to another user"],
        },
      })
    );

    await renderEditor(this);
    await click(".atcp-case-detail-edit-update__remove-existing");
    await click(".atcp-case-detail-edit-update__save");

    assert
      .dom(".atcp-case-detail-edit-update__remove-errors")
      .hasText("Attachment 4 is not part of this update");
    assert
      .dom(".atcp-case-detail-edit-update__upload-errors")
      .hasText("The attachment belongs to another user");
    assert.strictEqual(this.refreshes, 0);
  });

  test("disables save while an attachment is uploading", async function (assert) {
    pretender.post("/uploads.json", () =>
      response(500, { errors: ["Upload failed"] })
    );

    await renderEditor(this);
    await fillIn(
      ".atcp-case-detail-edit-update textarea",
      "Revised while uploading"
    );
    this.appEvents.trigger(
      uploadEventName(this),
      createFile("diagnostic.pdf", "application/pdf")
    );
    await waitFor(".atcp-case-detail-edit-update__file");

    assert
      .dom(".atcp-case-detail-edit-update__save")
      .isDisabled("saving is blocked while files upload");
    assert
      .dom(".atcp-case-detail-edit-update__upload-wait")
      .hasText("Wait for uploads to finish before saving changes.");

    await waitFor(".atcp-case-detail-edit-update__file-error");

    assert
      .dom(".atcp-case-detail-edit-update__save")
      .isNotDisabled("saving is enabled after uploads finish");
  });

  test("shows server update type errors on the field", async function (assert) {
    pretender.put("/atcp/cases/1/updates/29.json", () =>
      response(422, {
        errors: { update_type: ["Update type is required"] },
      })
    );

    await renderEditor(this);
    await fillIn(
      ".atcp-case-detail-edit-update .form-kit__field[data-name='update_type'] input",
      "Internal note"
    );
    await click(".atcp-case-detail-edit-update__save");

    assert
      .dom(
        ".atcp-case-detail-edit-update .form-kit__field[data-name='update_type'] .form-kit__errors"
      )
      .includesText("Update type is required");
  });

  test("shows server update type length errors on the field", async function (assert) {
    pretender.put("/atcp/cases/1/updates/29.json", () =>
      response(422, {
        errors: {
          update_type: ["Update type must be at most 100 characters"],
        },
      })
    );

    await renderEditor(this);
    await fillIn(
      ".atcp-case-detail-edit-update .form-kit__field[data-name='update_type'] input",
      "Internal note"
    );
    await click(".atcp-case-detail-edit-update__save");

    assert
      .dom(
        ".atcp-case-detail-edit-update .form-kit__field[data-name='update_type'] .form-kit__errors"
      )
      .includesText("Update type must be at most 100 characters");
  });

  test("confirms before discarding changes", async function (assert) {
    await renderEditor(this);
    await fillIn(
      ".atcp-case-detail-edit-update .form-kit__field[data-name='body'] textarea",
      "Draft change"
    );

    this.discard = false;
    await click(".atcp-case-detail-edit-update__cancel");

    assert.strictEqual(
      this.dialogParams.message,
      "Discard your changes to this update?"
    );
    assert.strictEqual(this.cancelled, 0, "keeps editing");

    this.discard = true;
    await click(".atcp-case-detail-edit-update__cancel");

    assert.strictEqual(this.cancelled, 1);
  });

  test("closes without confirmation when nothing changed", async function (assert) {
    await renderEditor(this);
    await click(".atcp-case-detail-edit-update__cancel");

    assert.strictEqual(this.dialogParams, null);
    assert.strictEqual(this.cancelled, 1);
    await settled();
  });

  test("reports dirty state while editing", async function (assert) {
    await renderEditor(this);
    await fillIn(
      ".atcp-case-detail-edit-update .form-kit__field[data-name='body'] textarea",
      "Draft change"
    );

    assert.true(this.dirtyChanges.at(-1), "a change marks the editor dirty");

    await fillIn(
      ".atcp-case-detail-edit-update .form-kit__field[data-name='body'] textarea",
      "Uploaded the requested evidence.\nSecond line."
    );

    assert.false(
      this.dirtyChanges.at(-1),
      "reverting the change clears the dirty state"
    );
  });

  test("cancels with Escape and confirms when there are changes", async function (assert) {
    await renderEditor(this);
    await triggerKeyEvent(".atcp-case-detail-edit-update", "keydown", "Escape");

    assert.strictEqual(this.dialogParams, null);
    assert.strictEqual(this.cancelled, 1, "an unchanged editor closes directly");

    this.cancelled = 0;
    this.dialogParams = null;
    this.discard = false;
    await fillIn(
      ".atcp-case-detail-edit-update .form-kit__field[data-name='body'] textarea",
      "Draft change"
    );
    await triggerKeyEvent(".atcp-case-detail-edit-update", "keydown", "Escape");

    assert.strictEqual(
      this.dialogParams.message,
      "Discard your changes to this update?"
    );
    assert.strictEqual(this.cancelled, 0, "keeps editing");

    this.discard = true;
    await triggerKeyEvent(".atcp-case-detail-edit-update", "keydown", "Escape");

    assert.strictEqual(this.cancelled, 1);
  });

  test("renders body-only mode without update type or attachments", async function (assert) {
    this.update = this.atcpCase.updates[2];
    this.bodyOnly = true;
    await renderEditor(this);

    assert
      .dom(
        ".atcp-case-detail-edit-update .form-kit__field[data-name='update_type']"
      )
      .doesNotExist();
    assert
      .dom(".atcp-case-detail-edit-update__attachments")
      .doesNotExist();
    assert
      .dom(
        ".atcp-case-detail-edit-update .form-kit__field[data-name='body'] textarea"
      )
      .exists();
  });

  test("sends only the body in body-only mode", async function (assert) {
    let submitted;

    this.update = {
      ...this.atcpCase.updates[2],
      body: "Original system note",
    };
    this.bodyOnly = true;

    pretender.put("/atcp/cases/1/updates/28.json", (request) => {
      submitted = parsePostData(request.requestBody);
      return response({ update: this.update });
    });

    await renderEditor(this);
    await fillIn(
      ".atcp-case-detail-edit-update .form-kit__field[data-name='body'] textarea",
      "  Updated system note  "
    );
    await click(".atcp-case-detail-edit-update__save");

    assert.deepEqual(submitted, { body: "Updated system note" });
  });

  test("requires a note when editing a reopened system update", async function (assert) {
    let requested = false;

    this.update = this.atcpCase.updates[5];
    this.bodyOnly = true;

    pretender.put("/atcp/cases/1/updates/25.json", () => {
      requested = true;
      return response({});
    });

    await renderEditor(this);
    await fillIn(
      ".atcp-case-detail-edit-update .form-kit__field[data-name='body'] textarea",
      "   "
    );
    await click(".atcp-case-detail-edit-update__save");

    assert.false(requested);
    assert
      .dom(
        ".atcp-case-detail-edit-update .form-kit__field[data-name='body'] .form-kit__errors"
      )
      .includesText("A note is required");
  });

  test("disables save when attachments already exceed the limit", async function (assert) {
    this.update = {
      ...this.update,
      attachments: Array.from({ length: 21 }, (_, index) => ({
        id: index + 1,
        original_filename: `file-${index}.pdf`,
        human_filesize: "1 KB",
      })),
    };

    await renderEditor(this);
    await fillIn(
      ".atcp-case-detail-edit-update .form-kit__field[data-name='body'] textarea",
      "Revised note"
    );

    assert
      .dom(".atcp-case-detail-edit-update__save")
      .isDisabled("the attachment limit is exceeded");
  });

  test("rejects undo when restoring an attachment would exceed the limit", async function (assert) {
    this.update = {
      ...this.update,
      attachments: Array.from({ length: 20 }, (_, index) => ({
        id: index + 1,
        original_filename: `file-${index}.pdf`,
        human_filesize: "1 KB",
      })),
    };

    pretender.post("/uploads.json", () => response(UPLOAD_RESPONSE));

    await renderEditor(this);
    await click(".atcp-case-detail-edit-update__remove-existing");

    const uploaded = new Promise((resolve) => {
      this.appEvents.one(uploadCompleteEventName(this), resolve);
    });
    this.appEvents.trigger(
      uploadEventName(this),
      createFile("diagnostic.pdf", "application/pdf")
    );
    await uploaded;
    await settled();

    await click(".atcp-case-detail-edit-update__undo-remove");

    assert
      .dom(".atcp-case-detail-edit-update__file-errors")
      .includesText("You can attach up to 20 files");
    assert
      .dom(".atcp-case-detail-edit-update__existing-file--removed")
      .exists({ count: 1 });
  });

  test("refreshes and announces when save is forbidden", async function (assert) {
    const announce = sinon.spy(this.a11y, "announce");

    pretender.put("/atcp/cases/1/updates/29.json", () =>
      response(403, { errors: ["Forbidden"] })
    );

    await renderEditor(this);
    await fillIn(
      ".atcp-case-detail-edit-update .form-kit__field[data-name='body'] textarea",
      "Revised note"
    );
    await click(".atcp-case-detail-edit-update__save");

    assert.strictEqual(this.refreshes, 1);
    assert.strictEqual(this.cancelled, 1);
    assert.true(
      announce.calledWith("This update can no longer be changed.", "polite")
    );
  });
});
