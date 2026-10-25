import { click, fillIn, render } from "@ember/test-helpers";
import { module, test } from "qunit";
import sinon from "sinon";
import { setupRenderingTest } from "discourse/tests/helpers/component-test";
import pretender, {
  response,
} from "discourse/tests/helpers/create-pretender";
import AtcpCaseDetailUpdate from "discourse/plugins/discourse-atcp-case/discourse/components/atcp-case/detail/update";
import { openCase } from "../../fixtures/atcp-case-detail";

const FORM_OPTIONS = {
  update_labels: ["Vendor communication", "Internal note"],
};

async function renderUpdate(context) {
  await render(
    <template>
      <AtcpCaseDetailUpdate
        @update={{context.update}}
        @atcpCase={{context.atcpCase}}
        @formOptions={{context.formOptions}}
      />
    </template>
  );
}

module("Integration | Component | AtcpCaseDetailUpdate", function (hooks) {
  setupRenderingTest(hooks, { stubRouter: true });

  hooks.beforeEach(function () {
    this.atcpCase = openCase();
    this.update = this.atcpCase.updates[1];
    this.formOptions = FORM_OPTIONS;
    this.currentUser = this.owner.lookup("service:current-user");
    this.currentUser.admin = false;
    this.router = this.owner.lookup("service:router");
    this.refreshes = 0;
    this.router.refresh = () => {
      this.refreshes += 1;
      return Promise.resolve();
    };
    this.dialog = this.owner.lookup("service:dialog");
    this.confirmed = true;
    this.deleteParams = null;
    this.dialog.deleteConfirm = (params) => {
      this.deleteParams = params;
      return Promise.resolve(this.confirmed);
    };
    this.a11y = this.owner.lookup("service:a11y");
  });

  test("shows Edit to internal users on open cases", async function (assert) {
    await renderUpdate(this);

    assert
      .dom(".atcp-case-detail__update-action")
      .hasText("Edit");
    assert
      .dom(".atcp-case-detail__update-action--danger")
      .doesNotExist("only admins can delete updates");
  });

  test("shows Delete to admins", async function (assert) {
    this.currentUser.admin = true;
    await renderUpdate(this);

    assert
      .dom(".atcp-case-detail__update-action--danger")
      .hasText("Delete");
  });

  test("hides edit actions for system updates and closed cases", async function (assert) {
    this.update = this.atcpCase.updates[0];
    await renderUpdate(this);

    assert.dom(".atcp-case-detail__update-action").doesNotExist();

    this.update = this.atcpCase.updates[1];
    this.atcpCase = { ...this.atcpCase, status: "Closed" };
    await renderUpdate(this);

    assert.dom(".atcp-case-detail__update-action").doesNotExist();
  });

  test("opens the inline editor and returns focus when cancelled", async function (assert) {
    await renderUpdate(this);

    await click(".atcp-case-detail__update-action");
    assert
      .dom(".atcp-case-detail-edit-update")
      .exists();
    assert
      .dom(
        ".atcp-case-detail-edit-update .form-kit__field[data-name='update_type'] input"
      )
      .hasValue("Vendor communication");
    assert.dom(".atcp-case-detail__update-body").doesNotExist();

    await click(".atcp-case-detail-edit-update__cancel");
    


    assert.dom(".atcp-case-detail-edit-update").doesNotExist();
    assert.dom(".atcp-case-detail__update-body").exists();
    assert
      .dom(".atcp-case-detail__update-action")
      .isFocused("focus returns to Edit");
  });

  test("deletes an update after confirmation", async function (assert) {
    let requested = false;

    this.currentUser.admin = true;
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
      "Delete this update? This cannot be undone."
    );
    assert.strictEqual(
      this.deleteParams.confirmButtonLabel,
      "atcp_case.cases.detail.edit_update.delete"
    );
  });

  test("does not delete when confirmation is cancelled", async function (assert) {
    let requested = false;

    this.currentUser.admin = true;
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

  test("announces when an edit is saved", async function (assert) {
    const announce = sinon.spy(this.a11y, "announce");

    pretender.put("/atcp/cases/1/updates/29.json", () =>
      response({ update: this.update })
    );

    await renderUpdate(this);
    await click(".atcp-case-detail__update-action");
    await fillIn(
      ".atcp-case-detail-edit-update .form-kit__field[data-name='body'] textarea",
      "Revised note"
    );
    await click(".atcp-case-detail-edit-update__save");
    


    assert.true(announce.calledWith("Update saved", "polite"));
    assert.dom(".atcp-case-detail-edit-update").doesNotExist();
  });
});
