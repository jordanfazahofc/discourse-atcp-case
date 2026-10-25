import { click, fillIn, render, settled } from "@ember/test-helpers";
import { module, test } from "qunit";
import { setupRenderingTest } from "discourse/tests/helpers/component-test";
import pretender, {
  parsePostData,
  response,
} from "discourse/tests/helpers/create-pretender";
import AtcpCaseDetailEditUpdate from "discourse/plugins/discourse-atcp-case/discourse/components/atcp-case/detail/edit-update";
import { openCase } from "../../fixtures/atcp-case-detail";

const FORM_OPTIONS = {
  update_labels: ["Vendor communication", "Internal note"],
};

async function renderEditor(context) {
  await render(
    <template>
      <AtcpCaseDetailEditUpdate
        @update={{context.update}}
        @atcpCase={{context.atcpCase}}
        @formOptions={{context.formOptions}}
        @onSaved={{context.onSaved}}
        @onCancel={{context.onCancel}}
      />
    </template>
  );
}

module("Integration | Component | AtcpCaseDetailEditUpdate", function (hooks) {
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
    this.saved = 0;
    this.onSaved = () => {
      this.saved += 1;
    };
    this.cancelled = 0;
    this.onCancel = () => {
      this.cancelled += 1;
    };
    this.dialog = this.owner.lookup("service:dialog");
    this.discard = true;
    this.dialogParams = null;
    this.dialog.confirm = (params) => {
      this.dialogParams = params;
      return Promise.resolve(this.discard);
    };
  });

  test("renders an editable text field with shared suggestions", async function (assert) {
    await renderEditor(this);

    assert
      .dom(
        ".atcp-case-detail-edit-update .form-kit__field[data-name='update_type'] input"
      )
      .hasValue("Vendor communication")
      .hasAttribute("maxlength", "100")
      .hasAttribute("list", "atcp-case-edit-update-type-options-29");
    assert
      .dom(
        ".atcp-case-detail-edit-update .form-kit__field[data-name='update_type'] datalist option"
      )
      .exists({ count: 2 });
    assert
      .dom(
        ".atcp-case-detail-edit-update .form-kit__field[data-name='update_type']"
      )
      .includesText("Type your own, or pick a suggestion.")
      .doesNotIncludeText("General note");
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
});
