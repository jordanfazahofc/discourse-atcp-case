import { click, fillIn, render, settled } from "@ember/test-helpers";
import { module, test } from "qunit";
import ModalContainer from "discourse/components/modal-container";
import { setupRenderingTest } from "discourse/tests/helpers/component-test";
import pretender, {
  parsePostData,
  response,
} from "discourse/tests/helpers/create-pretender";
import AtcpCaseReopenModal from "discourse/plugins/discourse-atcp-case/discourse/components/atcp-case/atcp-case-reopen-modal";
import { DETAIL_CASE } from "../../fixtures/atcp-case-detail";

const FIELD = ".atcp-case-reopen-modal .form-kit__field[data-name='reason']";

async function renderModal(context) {
  await render(
    <template>
      <ModalContainer />
    </template>
  );

  context.modal.show(AtcpCaseReopenModal, { model: context.model });
  await settled();
}

module("Integration | Component | AtcpCaseReopenModal", function (hooks) {
  setupRenderingTest(hooks, { stubRouter: true });

  hooks.beforeEach(function () {
    this.atcpCase = DETAIL_CASE;
    this.saved = 0;
    this.refreshes = 0;
    this.model = {
      atcpCase: this.atcpCase,
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

  test("renders the note and the reason field", async function (assert) {
    await renderModal(this);

    assert.dom(".d-modal__title-text").hasText("Reopen case");
    assert
      .dom(".atcp-case-reopen-modal__note")
      .hasText(
        "Reopening returns this case to In Progress and records the reason in the Progress Log."
      );
    assert.dom(`${FIELD} textarea`).hasAttribute("maxlength", "2000");
  });

  test("does not submit without a reason", async function (assert) {
    let requests = 0;
    pretender.post("/atcp/cases/1/reopen.json", () => {
      requests += 1;
      return response({ case: this.atcpCase });
    });

    await renderModal(this);
    await click(".atcp-case-reopen-modal__submit");

    assert.dom(`${FIELD} .form-kit__errors`).exists();
    assert.strictEqual(requests, 0);
    assert.notStrictEqual(this.modal.activeModal, null);
  });

  test("submits a trimmed reason and closes", async function (assert) {
    let submitted;
    pretender.post("/atcp/cases/1/reopen.json", (request) => {
      submitted = parsePostData(request.requestBody);
      return response({ case: this.atcpCase });
    });

    await renderModal(this);
    await fillIn(`${FIELD} textarea`, "  Customer replied  ");
    await click(".atcp-case-reopen-modal__submit");

    assert.deepEqual(submitted, { reason: "Customer replied" });
    assert.strictEqual(this.saved, 1);
    assert.strictEqual(this.modal.activeModal, null);
  });

  test("shows a reason error without refreshing", async function (assert) {
    pretender.post("/atcp/cases/1/reopen.json", () =>
      response(422, {
        errors: {
          reason: ["Reason is too long"],
        },
      })
    );

    await renderModal(this);
    await fillIn(`${FIELD} textarea`, "Customer replied");
    await click(".atcp-case-reopen-modal__submit");

    assert.dom(`${FIELD} .form-kit__errors`).hasText("Reason is too long");
    assert.strictEqual(this.refreshes, 0);
    assert.strictEqual(this.saved, 0);
    assert.notStrictEqual(this.modal.activeModal, null);
  });

  test("shows base errors and refreshes the case", async function (assert) {
    pretender.post("/atcp/cases/1/reopen.json", () =>
      response(422, {
        errors: {
          base: ["The case is not closed"],
        },
      })
    );

    await renderModal(this);
    await fillIn(`${FIELD} textarea`, "Customer replied");
    await click(".atcp-case-reopen-modal__submit");

    assert
      .dom(".atcp-case-reopen-modal__errors")
      .includesText("The case is not closed");
    assert.strictEqual(this.refreshes, 1);
    assert.strictEqual(this.saved, 0);
    assert.notStrictEqual(this.modal.activeModal, null);
  });

  test("closes and refreshes for a 404", async function (assert) {
    pretender.post("/atcp/cases/1/reopen.json", () =>
      response(404, { errors: ["Not found"] })
    );

    await renderModal(this);
    await fillIn(`${FIELD} textarea`, "Customer replied");
    await click(".atcp-case-reopen-modal__submit");

    assert.strictEqual(this.refreshes, 1);
    assert.strictEqual(this.saved, 0);
    assert.strictEqual(this.modal.activeModal, null);
  });

  test("confirms before discarding a reason", async function (assert) {
    await renderModal(this);
    await fillIn(`${FIELD} textarea`, "Customer replied");

    this.discard = false;
    await click(".atcp-case-reopen-modal__cancel");

    assert.notStrictEqual(this.modal.activeModal, null);
    assert.true(this.dialogParams.message.includes("Discard this reopen reason"));

    this.discard = true;
    await click(".atcp-case-reopen-modal__cancel");

    assert.strictEqual(this.modal.activeModal, null);
  });
});
