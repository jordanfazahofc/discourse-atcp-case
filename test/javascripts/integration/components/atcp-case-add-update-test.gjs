import {
  click,
  fillIn,
  render,
  settled,
  waitFor,
} from "@ember/test-helpers";
import { module, test } from "qunit";
import { setupRenderingTest } from "discourse/tests/helpers/component-test";
import pretender, {
  parsePostData,
  response,
} from "discourse/tests/helpers/create-pretender";
import { createFile } from "discourse/tests/helpers/qunit-helpers";
import AtcpCaseDetailAddUpdate from "discourse/plugins/discourse-atcp-case/discourse/components/atcp-case/detail/add-update";
import { openCase } from "../../fixtures/atcp-case-detail";

const FORM_OPTIONS = {
  update_labels: ["General note", "Vendor communication", "Internal note"],
  statuses: ["Open", "In Progress", "On Hold", "Solution Found", "Closed"],
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

async function renderForm(context) {
  await render(
    <template>
      <AtcpCaseDetailAddUpdate
        @atcpCase={{context.atcpCase}}
        @formOptions={{context.formOptions}}
      />
    </template>
  );
}

function uploadEventName(context) {
  return `upload-mixin:atcp-case-add-update-${context.atcpCase.id}:add-files`;
}

function uploadCompleteEventName(context) {
  return `upload-mixin:atcp-case-add-update-${context.atcpCase.id}:all-uploads-complete`;
}

async function addFileAndWait(context, fileName = "diagnostic.pdf") {
  const uploaded = new Promise((resolve) => {
    context.appEvents.one(uploadCompleteEventName(context), resolve);
  });

  context.appEvents.trigger(
    uploadEventName(context),
    createFile(fileName, "application/pdf")
  );

  await uploaded;
  await settled();
}

async function selectStatus(value) {
  const select = document.querySelector(
    ".atcp-case-detail-add-update select[name='status']"
  );
  select.value = value;
  select.dispatchEvent(new Event("change", { bubbles: true }));
}

module("Integration | Component | AtcpCaseDetailAddUpdate", function (hooks) {
  setupRenderingTest(hooks, { stubRouter: true });

  hooks.beforeEach(function () {
    this.atcpCase = openCase();
    this.formOptions = FORM_OPTIONS;
    this.appEvents = this.owner.lookup("service:app-events");
    this.router = this.owner.lookup("service:router");
    this.refreshes = 0;
    this.router.refresh = () => {
      this.refreshes += 1;
      return Promise.resolve();
    };
  });

  test("renders the form for an open case", async function (assert) {
    await renderForm(this);

    assert
      .dom(".atcp-case-detail-add-update__title")
      .hasText("Add update");
    assert
      .dom(".atcp-case-detail-add-update__submit")
      .hasText("Add update");
    assert
      .dom(".atcp-case-detail-add-update .form-kit__field[data-name='update_type'] select")
      .hasValue("General note");
    assert
      .dom(".atcp-case-detail-add-update select[name='status']")
      .hasValue("");

    const statusText = document.querySelector(
      ".atcp-case-detail-add-update select[name='status']"
    ).textContent;
    assert.true(statusText.includes("Keep current status"));
    assert.true(statusText.includes("In Progress"));
    assert.false(statusText.includes("Closed"), "closed is not offered");
    assert.false(statusText.includes("Open"), "the current status is excluded");
  });

  test("uses the first update label when General note is unavailable", async function (assert) {
    this.formOptions = {
      ...FORM_OPTIONS,
      update_labels: ["Vendor communication", "Internal note"],
    };

    await renderForm(this);

    assert
      .dom(".atcp-case-detail-add-update .form-kit__field[data-name='update_type'] select")
      .hasValue("Vendor communication");
  });

  test("shows the closed notice instead of the form", async function (assert) {
    this.atcpCase = { ...openCase(), status: "Closed" };
    await renderForm(this);

    assert
      .dom(".atcp-case-detail-add-update__closed")
      .hasText("This case is closed. Reopen it to add updates.");
    assert.dom(".atcp-case-detail-add-update form").doesNotExist();
  });

  test("requires a note or a completed attachment", async function (assert) {
    let requests = 0;
    pretender.post("/atcp/cases/1/updates.json", () => {
      requests += 1;
      return response({});
    });

    await renderForm(this);
    await click(".atcp-case-detail-add-update__submit");

    assert.strictEqual(requests, 0, "does not submit an empty update");
    assert
      .dom(".atcp-case-detail-add-update .form-kit__field[data-name='body'] .form-kit__errors")
      .hasText("Add a note or attach at least one file");
  });

  test("rejects disallowed files without uploading", async function (assert) {
    let uploads = 0;
    pretender.post("/uploads.json", () => {
      uploads += 1;
      return response(UPLOAD_RESPONSE);
    });

    await renderForm(this);
    this.appEvents.trigger(
      uploadEventName(this),
      createFile("malware.exe", "application/octet-stream")
    );
    await settled();

    assert.strictEqual(uploads, 0);
    assert
      .dom(".atcp-case-detail-add-update__file-errors")
      .hasText("malware.exe: file type not allowed");
    assert.dom(".atcp-case-detail-add-update__file").doesNotExist();
  });

  test("requeues duplicate file names only once", async function (assert) {
    pretender.post("/uploads.json", () => response(UPLOAD_RESPONSE));

    await renderForm(this);
    this.appEvents.trigger(
      uploadEventName(this),
      createFile("diagnostic.pdf", "application/pdf")
    );
    await waitFor(".atcp-case-detail-add-update__file");

    this.appEvents.trigger(
      uploadEventName(this),
      createFile("DIAGNOSTIC.PDF", "application/pdf")
    );
    await settled();

    assert.dom(".atcp-case-detail-add-update__file").exists({ count: 1 });
    assert
      .dom(".atcp-case-detail-add-update__file-errors")
      .hasText("DIAGNOSTIC.PDF: file already attached");
  });

  test("uploads an attachment and submits its upload id", async function (assert) {
    let submitted;
    let uploads = 0;

    pretender.post("/uploads.json", () => {
      uploads += 1;
      return response(UPLOAD_RESPONSE);
    });
    pretender.post("/atcp/cases/1/updates.json", (request) => {
      submitted = parsePostData(request.requestBody);
      return response({ status: "Open" });
    });

    await renderForm(this);

    const uploaded = new Promise((resolve) => {
      this.appEvents.one(
        "upload-mixin:atcp-case-add-update-1:all-uploads-complete",
        resolve
      );
    });

    this.appEvents.trigger(
      uploadEventName(this),
      createFile("diagnostic.pdf", "application/pdf")
    );

    await uploaded;
    await settled();

    assert.strictEqual(uploads, 1);
    assert
      .dom(".atcp-case-detail-add-update__file")
      .includesText("diagnostic.pdf");
    assert.dom(".atcp-case-detail-add-update__file-progress").doesNotExist();

    await click(".atcp-case-detail-add-update__submit");

    assert.deepEqual(submitted, {
      update_type: "General note",
      "upload_ids[]": ["501"],
    });
    assert.strictEqual(this.refreshes, 1, "refreshes the case");
    assert.dom(".atcp-case-detail-add-update__file").doesNotExist();
  });

  test("sends the note and the selected status", async function (assert) {
    let submitted;

    pretender.post("/atcp/cases/1/updates.json", (request) => {
      submitted = parsePostData(request.requestBody);
      return response({ status: "In Progress" });
    });

    await renderForm(this);
    await fillIn(
      ".atcp-case-detail-add-update .form-kit__field[data-name='body'] textarea",
      "  Diagnosed the fan curve.  "
    );
    await selectStatus("In Progress");
    await click(".atcp-case-detail-add-update__submit");

    assert.deepEqual(submitted, {
      update_type: "General note",
      body: "Diagnosed the fan curve.",
      status: "In Progress",
    });
  });

  test("matches an upload when the server returns a differently formatted filename", async function (assert) {
    pretender.post("/uploads.json", () =>
      response({
        ...UPLOAD_RESPONSE,
        original_filename: "  DIAGNOSTIC.PDF  ",
      })
    );

    await renderForm(this);
    await addFileAndWait(this, "diagnostic.pdf");

    assert
      .dom(".atcp-case-detail-add-update__file")
      .includesText("diagnostic.pdf");
    assert.dom(".atcp-case-detail-add-update__file-progress").doesNotExist();
    assert.dom(".atcp-case-detail-add-update__file-error").doesNotExist();
    assert
      .dom(".atcp-case-detail-add-update__submit")
      .isNotDisabled("the upload completed");
  });

  test("allows the same file to be selected again after removing it", async function (assert) {
    pretender.post("/uploads.json", () => response(UPLOAD_RESPONSE));

    await renderForm(this);
    await addFileAndWait(this, "diagnostic.pdf");

    await click(".atcp-case-detail-add-update__remove");
    assert.dom(".atcp-case-detail-add-update__file").doesNotExist();

    await addFileAndWait(this, "diagnostic.pdf");

    assert.dom(".atcp-case-detail-add-update__file").exists({ count: 1 });
    assert
      .dom(".atcp-case-detail-add-update__file-errors")
      .doesNotExist("the selection is not treated as a duplicate");
  });

  test("allows the same file to be selected again after a successful submit", async function (assert) {
    pretender.post("/uploads.json", () => response(UPLOAD_RESPONSE));
    pretender.post("/atcp/cases/1/updates.json", () =>
      response({ status: "Open" })
    );

    await renderForm(this);
    await addFileAndWait(this, "diagnostic.pdf");

    await click(".atcp-case-detail-add-update__submit");
    assert.dom(".atcp-case-detail-add-update__file").doesNotExist();
    assert.strictEqual(this.refreshes, 1);

    await addFileAndWait(this, "diagnostic.pdf");

    assert.dom(".atcp-case-detail-add-update__file").exists({ count: 1 });
    assert
      .dom(".atcp-case-detail-add-update__file-errors")
      .doesNotExist("the uploader state was cleared");
  });

  test("keeps the current status out of the payload", async function (assert) {
    let submitted;

    pretender.post("/atcp/cases/1/updates.json", (request) => {
      submitted = parsePostData(request.requestBody);
      return response({ status: "Open" });
    });

    await renderForm(this);
    await fillIn(
      ".atcp-case-detail-add-update .form-kit__field[data-name='body'] textarea",
      "Waiting for the branch."
    );
    await click(".atcp-case-detail-add-update__submit");

    assert.strictEqual(submitted.status, undefined);
  });

  test("does not submit an upload removed before saving", async function (assert) {
    let submitted;

    pretender.post("/uploads.json", () => response(UPLOAD_RESPONSE));
    pretender.post("/atcp/cases/1/updates.json", (request) => {
      submitted = parsePostData(request.requestBody);
      return response({ status: "Open" });
    });

    await renderForm(this);

    const uploaded = new Promise((resolve) => {
      this.appEvents.one(
        "upload-mixin:atcp-case-add-update-1:all-uploads-complete",
        resolve
      );
    });
    this.appEvents.trigger(
      uploadEventName(this),
      createFile("diagnostic.pdf", "application/pdf")
    );
    await uploaded;
    await settled();

    await click(".atcp-case-detail-add-update__remove");
    assert.dom(".atcp-case-detail-add-update__file").doesNotExist();

    await fillIn(
      ".atcp-case-detail-add-update .form-kit__field[data-name='body'] textarea",
      "The attachment was removed."
    );
    await click(".atcp-case-detail-add-update__submit");

    assert.strictEqual(submitted["upload_ids[]"], undefined);
  });

  test("disables submit while an upload is running and marks a failed upload", async function (assert) {
    pretender.post("/uploads.json", () =>
      response(500, { errors: ["Upload failed"] })
    );

    await renderForm(this);
    this.appEvents.trigger(
      uploadEventName(this),
      createFile("diagnostic.pdf", "application/pdf")
    );
    await waitFor(".atcp-case-detail-add-update__file");

    assert
      .dom(".atcp-case-detail-add-update__submit")
      .isDisabled("submitting is blocked while files upload");
    assert
      .dom(".atcp-case-detail-add-update__upload-wait")
      .hasText("Wait for uploads to finish before adding the update.");

    await waitFor(".atcp-case-detail-add-update__file-error");

    assert
      .dom(".atcp-case-detail-add-update__file-error")
      .hasText("diagnostic.pdf: upload failed");
    assert
      .dom(".atcp-case-detail-add-update__submit")
      .isNotDisabled("submitting is enabled after uploads finish");
  });

  test("renders server field and base errors", async function (assert) {
    pretender.post("/atcp/cases/1/updates.json", () =>
      response(422, {
        errors: {
          base: ["Unable to save this update"],
          update_type: ["Update type is invalid"],
          body: ["Provide a note or attach at least one file"],
          upload_ids: ["The attachment belongs to another user"],
        },
      })
    );

    await renderForm(this);
    await fillIn(
      ".atcp-case-detail-add-update .form-kit__field[data-name='body'] textarea",
      "Trying to save."
    );
    await click(".atcp-case-detail-add-update__submit");

    assert
      .dom(".atcp-case-detail-add-update__errors")
      .includesText("Unable to save this update");
    assert
      .dom(".atcp-case-detail-add-update__errors-list li")
      .exists({ count: 1 }, "base errors are not duplicated");
    assert
      .dom(".atcp-case-detail-add-update .form-kit__field[data-name='update_type'] .form-kit__errors")
      .hasText("Update type is invalid");
    assert
      .dom(".atcp-case-detail-add-update .form-kit__field[data-name='body'] .form-kit__errors")
      .hasText("Provide a note or attach at least one file");
    assert
      .dom(".atcp-case-detail-add-update__upload-errors")
      .hasText("The attachment belongs to another user");
    assert.strictEqual(this.refreshes, 0);
  });

  test("refreshes when the case was closed remotely", async function (assert) {
    pretender.post("/atcp/cases/1/updates.json", () =>
      response(422, {
        errors: ["This case is closed. Reopen it to make changes"],
      })
    );

    await renderForm(this);
    await fillIn(
      ".atcp-case-detail-add-update .form-kit__field[data-name='body'] textarea",
      "Trying to save."
    );
    await click(".atcp-case-detail-add-update__submit");

    assert
      .dom(".atcp-case-detail-add-update__errors")
      .includesText("This case is closed");
    assert.strictEqual(this.refreshes, 1);
  });
});
