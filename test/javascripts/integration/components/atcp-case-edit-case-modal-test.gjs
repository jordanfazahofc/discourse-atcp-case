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
import AtcpCaseEditCaseModal from "discourse/plugins/discourse-atcp-case/discourse/components/atcp-case/atcp-case-edit-case-modal";
import { openCase } from "../../fixtures/atcp-case-detail";

const FORM_OPTIONS = {
  case_types: ["Hardware defect", "Compatibility", "Hardware"],
  severities: ["Low", "Medium", "High", "Critical"],
};

const PIC_GROUPS = {
  groups: [
    {
      name: "Technical Support",
      users: [{ id: 5, username: "jordan", name: "Jordan" }],
    },
    {
      name: "Production",
      users: [{ id: 6, username: "rina", name: null }],
    },
  ],
};

const PRODUCTS = [
  { id: 11, name: "Axioo P15", sku_code: "AXIOO-P15" },
  { id: 12, name: "PRO L7 (NBAX22X)", sku_code: "NBAX22X" },
  { id: 13, name: "Axioo P17", sku_code: "AXIOO-P17" },
];

async function renderModal(context) {
  await render(
    <template>
      <ModalContainer />
    </template>
  );

  context.modal.show(AtcpCaseEditCaseModal, { model: context.model });
  await settled();
}

function selectedChips() {
  return [
    ...document.querySelectorAll(
      ".atcp-case-edit-case-modal .atcp-case-product-chooser .select-kit-header .selected-choice"
    ),
  ].map((chip) => chip.textContent.trim());
}

module("Integration | Component | AtcpCaseEditCaseModal", function (hooks) {
  setupRenderingTest(hooks, { stubRouter: true });

  hooks.beforeEach(function () {
    this.atcpCase = openCase();
    this.saved = 0;
    this.noLongerEditable = 0;
    this.refreshes = 0;
    this.model = {
      atcpCase: this.atcpCase,
      formOptions: FORM_OPTIONS,
      picGroups: PIC_GROUPS,
      onSaved: () => {
        this.saved += 1;
      },
      onNoLongerEditable: () => {
        this.noLongerEditable += 1;
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

    pretender.get("/atcp/products/search.json", () =>
      response({ products: PRODUCTS })
    );
  });

  hooks.afterEach(function () {
    if (this.modal.activeModal) {
      this.modal.close();
    }
  });

  test("renders the current values and orphan product note", async function (assert) {
    await renderModal(this);

    assert.dom(".d-modal__title-text").hasText("Edit case");
    assert
      .dom(
        ".atcp-case-edit-case-modal .form-kit__field[data-name='title'] input"
      )
      .hasValue("Fan noise on boot");
    assert.deepEqual(selectedChips(), [
      "Axioo P15 (AXIOO-P15)",
      "PRO L7 (NBAX22X)",
    ]);
    assert
      .dom(".atcp-case-edit-case-modal__orphan-products")
      .hasText(
        "No longer in the repository, kept on the case: Legacy Axioo"
      );
    assert
      .dom(".atcp-case-edit-case-modal__submit")
      .isDisabled("there are no changes yet");
  });

  test("keeps save disabled and sends no request without changes", async function (assert) {
    let requests = 0;

    pretender.put("/atcp/cases/1.json", () => {
      requests += 1;
      return response({ case: this.atcpCase });
    });

    await renderModal(this);

    assert
      .dom(".atcp-case-edit-case-modal__submit")
      .isDisabled("there are no changes yet");

    assert.strictEqual(requests, 0);
  });

  test("cancels without confirmation when there are no changes", async function (assert) {
    await renderModal(this);

    await click(".atcp-case-edit-case-modal__cancel");

    assert.strictEqual(this.modal.activeModal, null);
    assert.strictEqual(this.dialogParams, null);
  });

  test("confirms before discarding changes on cancel", async function (assert) {
    await renderModal(this);
    await fillIn(
      ".atcp-case-edit-case-modal .form-kit__field[data-name='title'] input",
      "Updated fan noise"
    );

    this.discard = false;
    await click(".atcp-case-edit-case-modal__cancel");

    assert.notStrictEqual(this.modal.activeModal, null);
    assert.true(
      this.dialogParams.message.includes("Discard your changes"),
      "asks for confirmation"
    );

    this.discard = true;
    await click(".atcp-case-edit-case-modal__cancel");

    assert.strictEqual(this.modal.activeModal, null);
  });

  test("confirms before closing with unsaved changes", async function (assert) {
    await renderModal(this);
    await fillIn(
      ".atcp-case-edit-case-modal .form-kit__field[data-name='title'] input",
      "Updated fan noise"
    );

    this.discard = false;
    await click(".modal-close");

    assert.notStrictEqual(this.modal.activeModal, null);

    this.discard = true;
    await click(".modal-close");

    assert.strictEqual(this.modal.activeModal, null);
  });

  test("sends only the title when editing a case with orphan products", async function (assert) {
    let submitted;

    pretender.put("/atcp/cases/1.json", (request) => {
      submitted = parsePostData(request.requestBody);
      return response({ case: this.atcpCase });
    });

    await renderModal(this);
    assert
      .dom(".atcp-case-edit-case-modal__orphan-products")
      .includesText("Legacy Axioo");

    await fillIn(
      ".atcp-case-edit-case-modal .form-kit__field[data-name='title'] input",
      "  Updated fan noise  "
    );
    await click(".atcp-case-edit-case-modal__submit");

    assert.deepEqual(submitted, { title: "Updated fan noise" });
    assert.strictEqual(this.saved, 1);
    assert.strictEqual(this.modal.activeModal, null);
  });

  test("sends product_ids only after the selection changes", async function (assert) {
    let submitted;

    pretender.put("/atcp/cases/1.json", (request) => {
      submitted = parsePostData(request.requestBody);
      return response({ case: this.atcpCase });
    });

    await renderModal(this);
    await click(
      ".atcp-case-edit-case-modal .atcp-case-product-chooser .select-kit-header .selected-choice[data-value='11']"
    );
    await click(".atcp-case-edit-case-modal__submit");

    assert.deepEqual(submitted, { "product_ids[]": ["12"] });
  });

  test("shows a product error and sends no request when all products are cleared", async function (assert) {
    let requests = 0;

    pretender.put("/atcp/cases/1.json", () => {
      requests += 1;
      return response({ case: this.atcpCase });
    });

    await renderModal(this);
    await click(
      ".atcp-case-edit-case-modal .atcp-case-product-chooser .select-kit-header .selected-choice[data-value='11']"
    );
    await click(
      ".atcp-case-edit-case-modal .atcp-case-product-chooser .select-kit-header .selected-choice[data-value='12']"
    );
    await click(".atcp-case-edit-case-modal__submit");

    assert
      .dom(
        ".atcp-case-edit-case-modal .form-kit__field[data-name='product_ids'] .form-kit__errors"
      )
      .includesText("At least one product is required");
    assert.strictEqual(requests, 0);
    assert.notStrictEqual(this.modal.activeModal, null);
  });

  test("sends an empty assignee_id when the PIC is cleared", async function (assert) {
    let submitted;

    this.atcpCase = openCase({
      assignee: { id: 5, username: "jordan", name: "Jordan" },
    });
    this.model.atcpCase = this.atcpCase;

    pretender.put("/atcp/cases/1.json", (request) => {
      submitted = parsePostData(request.requestBody);
      return response({ case: this.atcpCase });
    });

    await renderModal(this);

    const select = document.querySelector(".atcp-case-edit-case-modal__select");
    select.value = "";
    await triggerEvent(select, "change");
    await click(".atcp-case-edit-case-modal__submit");

    assert.deepEqual(submitted, { assignee_id: "" });
  });

  test("keeps an assignee who is no longer a PIC candidate", async function (assert) {
    this.atcpCase = openCase({
      assignee: { id: 99, username: "former", name: "Former PIC" },
    });
    this.model.atcpCase = this.atcpCase;

    await renderModal(this);

    assert
      .dom(
        ".atcp-case-edit-case-modal__select option[value='99']"
      )
      .hasText("Former PIC");
    assert
      .dom(".atcp-case-edit-case-modal__select optgroup[label='Current PIC']")
      .exists();
    assert
      .dom(".atcp-case-edit-case-modal__submit")
      .isDisabled("the current assignee is preserved without changes");
  });

  test("shows server field errors", async function (assert) {
    pretender.put("/atcp/cases/1.json", () =>
      response(422, {
        errors: {
          title: ["Title is already used"],
        },
      })
    );

    await renderModal(this);
    await fillIn(
      ".atcp-case-edit-case-modal .form-kit__field[data-name='title'] input",
      "Duplicate title"
    );
    await click(".atcp-case-edit-case-modal__submit");

    assert
      .dom(
        ".atcp-case-edit-case-modal .form-kit__field[data-name='title'] .form-kit__errors"
      )
      .hasText("Title is already used");
    assert.strictEqual(this.saved, 0);
  });

  test("keeps the modal open and refreshes after a base error", async function (assert) {
    pretender.put("/atcp/cases/1.json", () =>
      response(422, {
        errors: {
          base: ["The case is locked"],
        },
      })
    );

    await renderModal(this);
    await fillIn(
      ".atcp-case-edit-case-modal .form-kit__field[data-name='title'] input",
      "Updated title"
    );
    await click(".atcp-case-edit-case-modal__submit");

    assert
      .dom(".atcp-case-edit-case-modal__errors")
      .includesText("The case is locked");
    assert.notStrictEqual(this.modal.activeModal, null);
    assert.strictEqual(this.refreshes, 1);
    assert.strictEqual(this.saved, 0);
  });

  test("notifies when the case is no longer editable", async function (assert) {
    pretender.put("/atcp/cases/1.json", () =>
      response(403, { errors: ["Forbidden"] })
    );

    await renderModal(this);
    await fillIn(
      ".atcp-case-edit-case-modal .form-kit__field[data-name='title'] input",
      "Updated title"
    );
    await click(".atcp-case-edit-case-modal__submit");

    assert.strictEqual(this.noLongerEditable, 1);
    assert.strictEqual(this.saved, 0);
  });
});
