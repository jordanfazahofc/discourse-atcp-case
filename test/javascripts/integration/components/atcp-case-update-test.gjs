import { click, fillIn, render } from "@ember/test-helpers";
import { module, test } from "qunit";
import sinon from "sinon";
import { setupRenderingTest } from "discourse/tests/helpers/component-test";
import pretender, {
  response,
} from "discourse/tests/helpers/create-pretender";
import AtcpCaseDetailProgress from "discourse/plugins/discourse-atcp-case/discourse/components/atcp-case/detail/progress";
import AtcpCaseDetailUpdate from "discourse/plugins/discourse-atcp-case/discourse/components/atcp-case/detail/update";
import { openCase } from "../../fixtures/atcp-case-detail";

const FORM_OPTIONS = {
  statuses: ["Open", "In Progress", "On Hold", "Solution Found", "Closed"],
  upload: { extensions: ["pdf", "png"], max_mb: 2 },
};

async function renderUpdate(context) {
  await render(
    <template>
      <AtcpCaseDetailUpdate
        @update={{context.update}}
        @atcpCase={{context.atcpCase}}
        @isEditing={{false}}
        @onStartEdit={{context.onStartEdit}}
        @onStopEdit={{context.onStopEdit}}
        @onDirtyChange={{context.onDirtyChange}}
      />
    </template>
  );
}

async function renderProgress(context) {
  await render(
    <template>
      <AtcpCaseDetailProgress
        @atcpCase={{context.atcpCase}}
        @updates={{context.atcpCase.updates}}
        @formOptions={{context.formOptions}}
      />
    </template>
  );
}

function withSecondUserUpdate(context) {
  const first = context.atcpCase.updates[1];
  const second = {
    ...first,
    id: 31,
    body: "Second entry",
    details: {},
    edited_at: null,
    created_at: "2026-07-14T09:15:00",
  };

  context.atcpCase = {
    ...context.atcpCase,
    updates: [second, ...context.atcpCase.updates],
  };
}

module("Integration | Component | AtcpCaseDetailUpdate", function (hooks) {
  setupRenderingTest(hooks, { stubRouter: true });

  hooks.beforeEach(function () {
    this.atcpCase = openCase();
    this.update = this.atcpCase.updates[1];
    this.formOptions = FORM_OPTIONS;
    this.router = this.owner.lookup("service:router");
    this.refreshes = 0;
    this.router.refresh = () => {
      this.refreshes += 1;
      return Promise.resolve();
    };
    this.dialog = this.owner.lookup("service:dialog");
    this.confirmed = true;
    this.deleteParams = null;
    this.confirmParams = null;
    this.dialog.deleteConfirm = (params) => {
      this.deleteParams = params;
      return Promise.resolve(this.confirmed);
    };
    this.dialog.confirm = (params) => {
      this.confirmParams = params;
      return Promise.resolve(this.confirmed);
    };
    this.a11y = this.owner.lookup("service:a11y");
    this.onStartEdit = () => {};
    this.onStopEdit = () => {};
    this.onDirtyChange = () => {};
  });

  test("shows Edit and Delete from update permissions", async function (assert) {
    await renderUpdate(this);

    assert.dom("#atcp-case-update-edit-29").hasText("Edit");
    assert
      .dom(".atcp-case-detail__update-action--danger")
      .hasText("Delete");
  });

  test("renders Edit and Delete independently", async function (assert) {
    this.update = {
      ...this.update,
      can_edit: true,
      can_delete: false,
    };
    await renderUpdate(this);

    assert.dom("#atcp-case-update-edit-29").exists();
    assert.dom(".atcp-case-detail__update-action--danger").doesNotExist();

    this.update = {
      ...this.update,
      can_edit: false,
      can_delete: true,
    };
    await renderUpdate(this);

    assert.dom("#atcp-case-update-edit-29").doesNotExist();
    assert.dom(".atcp-case-detail__update-action--danger").exists();

    this.update = {
      ...this.update,
      can_edit: false,
      can_delete: false,
    };
    await renderUpdate(this);

    assert.dom(".atcp-case-detail__update-action").doesNotExist();
  });

  test("labels edit and delete actions with the update type and time", async function (assert) {
    this.update = {
      ...this.update,
      created_at: "2026-07-14T08:00:00",
    };
    await renderUpdate(this);

    assert
      .dom("#atcp-case-update-edit-29")
      .hasAttribute(
        "aria-label",
        "Edit Vendor communication update from 14 Jul 2026, 08:00"
      );
    assert
      .dom(".atcp-case-detail__update-action--danger")
      .hasAttribute(
        "aria-label",
        "Delete Vendor communication update from 14 Jul 2026, 08:00"
      );
  });

  test("shows actions for system updates when permitted", async function (assert) {
    this.update = this.atcpCase.updates[0];
    await renderUpdate(this);

    assert.dom("#atcp-case-update-edit-30").hasText("Edit");
    assert.dom(".atcp-case-detail__update-action--danger").hasText("Delete");
  });

  test("hides actions for closed cases even when permitted", async function (assert) {
    this.atcpCase = { ...this.atcpCase, status: "Closed" };
    await renderUpdate(this);

    assert.dom(".atcp-case-detail__update-action").doesNotExist();
  });

  test("shows previous versions newest first with plain text and attachment changes", async function (assert) {
    this.update = {
      ...this.update,
      details: {
        edit_history: [
          {
            edited_at: "2026-07-14T08:30:00",
            previous_update_type: "Internal note",
            previous_body: "<b>First</b> draft",
            added_attachments: [{ upload_id: 1, filename: "old-log.txt" }],
            removed_attachments: [
              { upload_id: 2, filename: "old-photo.jpg" },
            ],
          },
          {
            edited_at: "2026-07-14T08:45:00",
            previous_update_type: "Vendor communication",
            previous_body: "Second draft",
          },
        ],
      },
    };

    await renderUpdate(this);

    assert
      .dom(".atcp-case-detail__history-summary")
      .hasText("Previous versions (2)");
    const entries = Array.from(
      document.querySelectorAll(".atcp-case-detail__history-entry")
    );
    assert.strictEqual(entries.length, 2);
    assert.true(entries[0].textContent.includes("14 Jul 2026, 08:45"));
    assert.true(entries[0].textContent.includes("Second draft"));
    assert.true(entries[1].textContent.includes("Internal note"));
    assert.true(entries[1].textContent.includes("<b>First</b> draft"));
    assert.true(entries[1].textContent.includes("Added: old-log.txt"));
    assert.true(entries[1].textContent.includes("Removed: old-photo.jpg"));
    assert.dom(".atcp-case-detail__history-entry b").doesNotExist();
  });

  test("shows body, edited marker, and history for system updates", async function (assert) {
    this.update = {
      ...this.atcpCase.updates[2],
      body: "System note",
      edited_at: "2026-07-13T05:00:00.000Z",
      details: {
        edit_history: [
          {
            edited_at: "2026-07-13T04:30:00",
            previous_body: "Earlier system note",
          },
        ],
      },
    };
    await renderUpdate(this);

    assert
      .dom(".atcp-case-detail__system-update-body")
      .hasText("System note");
    assert.dom(".atcp-case-detail__edited").hasText("edited");
    assert
      .dom(".atcp-case-detail__history-summary")
      .hasText("Previous versions (1)");
    assert
      .dom(".atcp-case-detail__history-body")
      .hasText("Earlier system note");
  });

  test("shows No note when a system update was edited from an empty body", async function (assert) {
    this.update = {
      ...this.atcpCase.updates[2],
      edited_at: "2026-07-13T05:00:00.000Z",
      details: {
        edit_history: [
          {
            edited_at: "2026-07-13T04:30:00",
            previous_update_type: null,
            previous_body: null,
          },
        ],
      },
    };
    await renderUpdate(this);

    assert
      .dom(".atcp-case-detail__history-summary")
      .hasText("Previous versions (1)");
    assert
      .dom(".atcp-case-detail__history-body")
      .hasText("No note")
      .hasClass("atcp-case-detail__history-empty-version");
  });

  test("does not show body when a system update has no body", async function (assert) {
    this.update = this.atcpCase.updates[2];
    await renderUpdate(this);

    assert.dom(".atcp-case-detail__system-update-body").doesNotExist();
  });

  test("does not show edit history for malformed data", async function (assert) {
    this.update = {
      ...this.update,
      details: { edit_history: "unexpected" },
    };
    await renderUpdate(this);

    assert.dom(".atcp-case-detail__history").doesNotExist();
    assert.dom(".atcp-case-detail__update-body").exists();
  });

  test("opens a body-only editor for system updates", async function (assert) {
    await renderProgress(this);

    await click("#atcp-case-update-edit-28");

    assert.dom(".atcp-case-detail-edit-update").exists({ count: 1 });
    assert
      .dom(
        ".atcp-case-detail-edit-update .form-kit__field[data-name='update_type']"
      )
      .doesNotExist("system edits do not expose update type");
    assert
      .dom(".atcp-case-detail-edit-update__attachments")
      .doesNotExist("system edits do not expose attachments");
  });

  test("opens only one inline editor and confirms before switching dirty editors", async function (assert) {
    withSecondUserUpdate(this);
    await renderProgress(this);

    await click("#atcp-case-update-edit-31");
    assert.dom(".atcp-case-detail-edit-update").exists({ count: 1 });
    assert
      .dom(
        ".atcp-case-detail-edit-update .form-kit__field[data-name='body'] textarea"
      )
      .hasValue("Second entry");

    await fillIn(
      ".atcp-case-detail-edit-update .form-kit__field[data-name='body'] textarea",
      "Unsaved second entry"
    );
    this.confirmed = false;
    await click("#atcp-case-update-edit-29");

    assert.strictEqual(
      this.confirmParams.message,
      "Discard unsaved changes?"
    );
    assert.strictEqual(
      this.confirmParams.confirmButtonLabel,
      "atcp_case.cases.detail.edit_update.discard"
    );
    assert.strictEqual(
      this.confirmParams.cancelButtonLabel,
      "atcp_case.cases.detail.edit_update.keep_editing"
    );
    assert.dom(".atcp-case-detail-edit-update").exists({ count: 1 });
    assert
      .dom(
        ".atcp-case-detail-edit-update .form-kit__field[data-name='body'] textarea"
      )
      .hasValue("Unsaved second entry");

    this.confirmed = true;
    await click("#atcp-case-update-edit-29");


    assert.dom(".atcp-case-detail-edit-update").exists({ count: 1 });
    assert
      .dom(
        ".atcp-case-detail-edit-update .form-kit__field[data-name='body'] textarea"
      )
      .hasValue("Uploaded the requested evidence.\nSecond line.");
  });

  test("switches editors directly when there are no unsaved changes", async function (assert) {
    withSecondUserUpdate(this);
    await renderProgress(this);

    await click("#atcp-case-update-edit-31");
    await click("#atcp-case-update-edit-29");

    assert.strictEqual(this.confirmParams, null, "does not confirm");
    assert.dom(".atcp-case-detail-edit-update").exists({ count: 1 });
    assert
      .dom(
        ".atcp-case-detail-edit-update .form-kit__field[data-name='body'] textarea"
      )
      .hasValue("Uploaded the requested evidence.\nSecond line.");
  });

  test("returns focus to Edit when the editor is cancelled", async function (assert) {
    await renderProgress(this);

    await click("#atcp-case-update-edit-29");
    assert.dom(".atcp-case-detail-edit-update").exists();
    assert.dom(".atcp-case-detail__update-body").doesNotExist();

    await click(".atcp-case-detail-edit-update__cancel");

    assert.dom(".atcp-case-detail-edit-update").doesNotExist();
    assert.dom(".atcp-case-detail__update-body").exists();
    assert
      .dom("#atcp-case-update-edit-29")
      .isFocused("focus returns to Edit");
  });

  test("deletes an update after confirmation", async function (assert) {
    let requested = false;

    pretender.delete("/atcp/cases/1/updates/29.json", () => {
      requested = true;
      return response(204);
    });

    await renderUpdate(this);
    await click(".atcp-case-detail__update-action--danger");

    assert.true(requested);
    assert.strictEqual(this.refreshes, 1);
    assert.strictEqual(
      this.deleteParams.message,
      "Delete this update? It will be hidden from the log and recorded in the staff action log."
    );
    assert.strictEqual(
      this.deleteParams.confirmButtonLabel,
      "atcp_case.cases.detail.edit_update.delete"
    );
  });

  test("does not delete when confirmation is cancelled", async function (assert) {
    let requested = false;

    this.confirmed = false;
    pretender.delete("/atcp/cases/1/updates/29.json", () => {
      requested = true;
      return response(204);
    });

    await renderUpdate(this);
    await click(".atcp-case-detail__update-action--danger");

    assert.false(requested);
    assert.strictEqual(this.refreshes, 0);
  });

  test("uses the system delete confirmation for system updates", async function (assert) {
    pretender.delete("/atcp/cases/1/updates/28.json", () => response(204));

    this.update = this.atcpCase.updates[2];
    await renderUpdate(this);
    await click(".atcp-case-detail__update-action--danger");

    assert.strictEqual(
      this.deleteParams.message,
      "Delete this system update? The case status will not change; only this log row will be hidden. This will be recorded in the staff action log."
    );
    assert.strictEqual(
      this.deleteParams.confirmButtonLabel,
      "atcp_case.cases.detail.edit_update.delete"
    );
  });

  test("refreshes and announces when delete is forbidden", async function (assert) {
    const announce = sinon.spy(this.a11y, "announce");

    pretender.delete("/atcp/cases/1/updates/29.json", () =>
      response(403, { errors: ["Forbidden"] })
    );

    await renderUpdate(this);
    await click(".atcp-case-detail__update-action--danger");

    assert.strictEqual(this.refreshes, 1);
    assert.true(
      announce.calledWith("This update can no longer be changed.", "polite")
    );
  });

  test("refreshes and announces when the update no longer exists", async function (assert) {
    const announce = sinon.spy(this.a11y, "announce");

    pretender.delete("/atcp/cases/1/updates/29.json", () =>
      response(404, { errors: ["Not found"] })
    );

    await renderUpdate(this);
    await click(".atcp-case-detail__update-action--danger");


    assert.strictEqual(this.refreshes, 1);
    assert.true(
      announce.calledWith("This update no longer exists.", "polite")
    );
  });

  test("refreshes and announces a server delete error", async function (assert) {
    const announce = sinon.spy(this.a11y, "announce");

    pretender.delete("/atcp/cases/1/updates/29.json", () =>
      response(422, { errors: { base: ["Case is closed"] } })
    );

    await renderUpdate(this);
    await click(".atcp-case-detail__update-action--danger");


    assert.strictEqual(this.refreshes, 1);
    assert.true(announce.calledWith("Case is closed", "polite"));
  });

  test("announces when an edit is saved", async function (assert) {
    const announce = sinon.spy(this.a11y, "announce");

    pretender.put("/atcp/cases/1/updates/29.json", () =>
      response({ update: this.update })
    );

    await renderProgress(this);
    await click("#atcp-case-update-edit-29");
    await fillIn(
      ".atcp-case-detail-edit-update .form-kit__field[data-name='body'] textarea",
      "Revised note"
    );
    await click(".atcp-case-detail-edit-update__save");


    assert.true(announce.calledWith("Update saved", "polite"));
    assert.dom(".atcp-case-detail-edit-update").doesNotExist();
  });
});
