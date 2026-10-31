import {
  click,
  fillIn,
  render,
  settled,
  triggerEvent,
} from "@ember/test-helpers";
import { module, test } from "qunit";
import ModalContainer from "discourse/components/modal-container";
import { setupRenderingTest } from "discourse/tests/helpers/component-test";
import pretender, {
  parsePostData,
  response,
} from "discourse/tests/helpers/create-pretender";
import AtcpCaseCloseModal from "discourse/plugins/discourse-atcp-case/discourse/components/atcp-case/atcp-case-close-modal";
import { openCase } from "../../fixtures/atcp-case-detail";

async function renderModal(context) {
  await render(
    <template>
      <ModalContainer />
    </template>
  );

  context.modal.show(AtcpCaseCloseModal, { model: context.model });
  await settled();
}

async function selectReason(reason) {
  const select = document.querySelector(`${field("close_reason")} select`);
  select.value = reason;
  await triggerEvent(select, "input");
}

function field(name) {
  return `.atcp-case-close-modal .form-kit__field[data-name='${name}']`;
}

module("Integration | Component | AtcpCaseCloseModal", function (hooks) {
  setupRenderingTest(hooks, { stubRouter: true });

  hooks.beforeEach(function () {
    this.atcpCase = openCase({ solution: null, root_cause_summary: null });
    this.saved = 0;
    this.refreshes = 0;
    this.model = {
      atcpCase: this.atcpCase,
      formOptions: { close_reasons: ["Resolved", "Duplicate", "Won't Fix"] },
      onSaved: () => {
        this.saved += 1;
      },
    };
    this.modal = this.owner.lookup("service:modal");
    this.router = this.owner.lookup("service:router");
    this.router.refresh = () => {
      this.refreshes += 1;
      return Promise.resolve();
    };
    this.dialog = this.owner.lookup("service:dialog");
    this.discard = true;
    this.dialogParams = null;
    this.dialog.confirm = (params) => {
      this.dialogParams = params;
      return Promise.resolve(this.discard);
    };
  });

  hooks.afterEach(function () {
    if (this.modal.activeModal) {
      this.modal.close();
    }
  });

  test("renders the fields in order and preloads current values", async function (assert) {
    this.atcpCase = openCase({
      solution: "Update the EC firmware.",
      root_cause_summary: "Fan curve was too aggressive.",
    });
    this.model.atcpCase = this.atcpCase;
    await renderModal(this);

    assert.dom(".d-modal__title-text").hasText("Close case");
    assert.deepEqual(
      [...document.querySelectorAll(".atcp-case-close-modal .form-kit__field")].map(
        (element) => element.dataset.name
      ),
      [
        "close_reason",
        "solution",
        "root_cause_summary",
        "workaround",
        "conclusion",
      ]
    );
    assert.dom(`${field("solution")} textarea`).hasValue(
      "Update the EC firmware."
    );
    assert.dom(`${field("root_cause_summary")} textarea`).hasValue(
      "Fan curve was too aggressive."
    );
    assert
      .dom(`${field("close_reason")} select option:first-child`)
      .hasText("Select a reason");
  });

  test("requires a solution when closing as Resolved", async function (assert) {
    let requests = 0;
    pretender.post("/atcp/cases/1/close.json", () => {
      requests += 1;
      return response({ case: this.atcpCase });
    });

    await renderModal(this);
    await selectReason("Resolved");
    await click(".atcp-case-close-modal__submit");

    assert
      .dom(`${field("solution")} .form-kit__errors`)
      .includesText("Solution is required when closing as Resolved.");
    assert.strictEqual(requests, 0);
    assert.notStrictEqual(this.modal.activeModal, null);
  });

  test("does not require a solution for other reasons", async function (assert) {
    let submitted;
    pretender.post("/atcp/cases/1/close.json", (request) => {
      submitted = parsePostData(request.requestBody);
      return response({ case: this.atcpCase });
    });

    await renderModal(this);
    await selectReason("Duplicate");
    await click(".atcp-case-close-modal__submit");

    assert.deepEqual(submitted, { close_reason: "Duplicate" });
    assert.strictEqual(this.saved, 1);
    assert.strictEqual(this.modal.activeModal, null);
  });

  test("submits only changed optional fields", async function (assert) {
    let submitted;
    this.atcpCase = openCase({
      solution: null,
      root_cause_summary: "Old root cause",
      workaround: null,
      conclusion: "Old conclusion",
    });
    this.model.atcpCase = this.atcpCase;
    pretender.post("/atcp/cases/1/close.json", (request) => {
      submitted = parsePostData(request.requestBody);
      return response({ case: this.atcpCase });
    });

    await renderModal(this);
    await selectReason("Duplicate");
    await fillIn(`${field("solution")} textarea`, "  New solution  ");
    await fillIn(
      `${field("root_cause_summary")} textarea`,
      "  Old root cause  "
    );
    await fillIn(`${field("workaround")} textarea`, "Disable turbo mode");
    await fillIn(`${field("conclusion")} textarea`, "  Old conclusion  ");
    await click(".atcp-case-close-modal__submit");

    assert.deepEqual(submitted, {
      close_reason: "Duplicate",
      solution: "New solution",
      workaround: "Disable turbo mode",
    });
  });

  test("shows field errors without refreshing", async function (assert) {
    pretender.post("/atcp/cases/1/close.json", () =>
      response(422, {
        errors: {
          close_reason: ["Close reason is invalid"],
        },
      })
    );

    await renderModal(this);
    await selectReason("Duplicate");
    await click(".atcp-case-close-modal__submit");

    assert
      .dom(`${field("close_reason")} .form-kit__errors`)
      .hasText("Close reason is invalid");
    assert.strictEqual(this.refreshes, 0);
    assert.strictEqual(this.saved, 0);
    assert.notStrictEqual(this.modal.activeModal, null);
  });

  test("shows base errors and refreshes the case", async function (assert) {
    pretender.post("/atcp/cases/1/close.json", () =>
      response(422, {
        errors: {
          base: ["The case is already closed"],
        },
      })
    );

    await renderModal(this);
    await selectReason("Duplicate");
    await click(".atcp-case-close-modal__submit");

    assert
      .dom(".atcp-case-close-modal__errors")
      .includesText("The case is already closed");
    assert.strictEqual(this.refreshes, 1);
    assert.strictEqual(this.saved, 0);
    assert.notStrictEqual(this.modal.activeModal, null);
  });

  test("closes and refreshes when access is lost", async function (assert) {
    pretender.post("/atcp/cases/1/close.json", () =>
      response(403, { errors: ["Forbidden"] })
    );

    await renderModal(this);
    await selectReason("Duplicate");
    await click(".atcp-case-close-modal__submit");

    assert.strictEqual(this.refreshes, 1);
    assert.strictEqual(this.saved, 0);
    assert.strictEqual(this.modal.activeModal, null);
  });

  test("closes and refreshes for a 404", async function (assert) {
    pretender.post("/atcp/cases/1/close.json", () =>
      response(404, { errors: ["Not found"] })
    );

    await renderModal(this);
    await selectReason("Duplicate");
    await click(".atcp-case-close-modal__submit");

    assert.strictEqual(this.refreshes, 1);
    assert.strictEqual(this.saved, 0);
    assert.strictEqual(this.modal.activeModal, null);
  });

  test("confirms before discarding a selected reason", async function (assert) {
    await renderModal(this);
    await selectReason("Duplicate");

    this.discard = false;
    await click(".atcp-case-close-modal__cancel");

    assert.notStrictEqual(this.modal.activeModal, null);
    assert.true(this.dialogParams.message.includes("Discard your changes"));

    this.discard = true;
    await click(".atcp-case-close-modal__cancel");

    assert.strictEqual(this.modal.activeModal, null);
  });
});
