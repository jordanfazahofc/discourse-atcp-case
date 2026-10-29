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
import AtcpCaseEditTechnicalModal from "discourse/plugins/discourse-atcp-case/discourse/components/atcp-case/atcp-case-edit-technical-modal";
import { openCase } from "../../fixtures/atcp-case-detail";

const FORM_OPTIONS = {
  frequencies: ["Intermittent", "Always", "Specific conditions"],
  reproducibilities: ["Reproducible", "Not reproducible", "Not tried"],
};

function atcpCase(overrides = {}) {
  return openCase({
    symptom: "Fan noise starts immediately after power on.",
    frequency: "Always",
    reproducibility: "Reproducible",
    non_trigger_conditions: null,
    bios_version: "1.2.3",
    os_driver_info: null,
    ...overrides,
  });
}

function field(name) {
  return `.atcp-case-edit-technical-modal .form-kit__field[data-name='${name}']`;
}

async function renderModal(context) {
  await render(
    <template>
      <ModalContainer />
    </template>
  );

  context.modal.show(AtcpCaseEditTechnicalModal, { model: context.model });
  await settled();
}

async function selectValue(name, value) {
  const select = document.querySelector(`${field(name)} select`);
  select.value = value;
  await triggerEvent(select, "change");
}

module(
  "Integration | Component | AtcpCaseEditTechnicalModal",
  function (hooks) {
    setupRenderingTest(hooks, { stubRouter: true });

    hooks.beforeEach(function () {
      this.atcpCase = atcpCase();
      this.saved = 0;
      this.noLongerEditable = 0;
      this.refreshes = 0;
      this.model = {
        atcpCase: this.atcpCase,
        formOptions: FORM_OPTIONS,
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
    });

    hooks.afterEach(function () {
      if (this.modal.activeModal) {
        this.modal.close();
      }
    });

    test("renders the fields, options, and initial values", async function (assert) {
      await renderModal(this);

      assert.dom(".d-modal__title-text").hasText("Edit technical details");
      assert
        .dom(".atcp-case-edit-technical-modal .form-kit__field")
        .exists({ count: 6 });
      assert.deepEqual(
        [
          ...document.querySelectorAll(
            ".atcp-case-edit-technical-modal .form-kit__container-title"
          ),
        ].map((label) => label.querySelector("span").textContent.trim()),
        [
          "Symptom",
          "Frequency",
          "Reproducibility",
          "Non-trigger conditions",
          "BIOS version",
          "OS / driver info",
        ],
        "renders every field label in order"
      );

      assert
        .dom(`${field("symptom")} textarea`)
        .hasValue("Fan noise starts immediately after power on.");
      assert.dom(`${field("frequency")} select`).hasValue("Always");
      assert
        .dom(`${field("reproducibility")} select`)
        .hasValue("Reproducible");
      assert.dom(`${field("non_trigger_conditions")} textarea`).hasValue("");
      assert.dom(`${field("bios_version")} input`).hasValue("1.2.3");
      assert.dom(`${field("os_driver_info")} textarea`).hasValue("");

      const frequencyOptions = [
        ...document.querySelectorAll(`${field("frequency")} option`),
      ];
      assert.dom(frequencyOptions[0]).hasText("Not set");
      assert.deepEqual(
        frequencyOptions.map((option) => option.textContent.trim()),
        ["Not set", "Intermittent", "Always", "Specific conditions"],
        "renders the Not set option before the form options"
      );

      assert.strictEqual(
        document.activeElement,
        document.querySelector(`${field("symptom")} textarea`),
        "the symptom field receives initial focus"
      );
    });

    test("submits only changed fields and closes", async function (assert) {
      let submitted;

      pretender.put("/atcp/cases/1.json", (request) => {
        submitted = parsePostData(request.requestBody);
        return response({ case: { id: 1 } });
      });

      await renderModal(this);
      await fillIn(`${field("symptom")} textarea`, "  Updated fan noise.  ");
      await selectValue("frequency", "Intermittent");
      await fillIn(`${field("bios_version")} input`, "2.0.0");
      await click(".atcp-case-edit-technical-modal__save");

      assert.deepEqual(submitted, {
        symptom: "Updated fan noise.",
        frequency: "Intermittent",
        bios_version: "2.0.0",
      });
      assert.strictEqual(this.modal.activeModal, null, "closes the dialog");
      assert.strictEqual(this.saved, 1, "notifies the parent");
      assert.strictEqual(this.noLongerEditable, 0);
    });

    test("closes without a request when nothing changed", async function (assert) {
      let requests = 0;

      pretender.put("/atcp/cases/1.json", () => {
        requests += 1;
        return response({ case: { id: 1 } });
      });

      await renderModal(this);
      await click(".atcp-case-edit-technical-modal__save");

      assert.strictEqual(requests, 0, "does not submit an empty payload");
      assert.strictEqual(this.modal.activeModal, null, "closes the dialog");
      assert.strictEqual(this.saved, 0, "does not reload the case");
    });

    test("shows field errors inline and other errors in the alert", async function (assert) {
      pretender.put("/atcp/cases/1.json", () =>
        response(422, {
          errors: {
            symptom: ["is not detailed enough"],
            unknown_field: ["is invalid"],
            base: ["Unable to save technical details"],
          },
        })
      );

      await renderModal(this);
      await fillIn(`${field("symptom")} textarea`, "Updated fan noise.");
      await click(".atcp-case-edit-technical-modal__save");

      assert.notStrictEqual(
        this.modal.activeModal,
        null,
        "keeps the dialog open"
      );
      assert
        .dom(`${field("symptom")} .form-kit__errors`)
        .hasText("is not detailed enough");

      const alert = document.querySelector(
        ".atcp-case-edit-technical-modal__errors"
      );
      assert.strictEqual(alert.getAttribute("role"), "alert");
      assert.true(alert.textContent.includes("Unable to save technical details"));
      assert.true(alert.textContent.includes("Unknown field: is invalid"));
      assert.false(alert.textContent.includes("is not detailed enough"));
      assert.strictEqual(
        this.refreshes,
        0,
        "does not refresh for a normal validation error"
      );
    });

    test("refreshes but stays open when a base error says the case is closed", async function (assert) {
      pretender.put("/atcp/cases/1.json", () =>
        response(422, {
          errors: {
            base: ["Case is closed"],
          },
        })
      );

      await renderModal(this);
      await fillIn(`${field("symptom")} textarea`, "Updated fan noise.");
      await click(".atcp-case-edit-technical-modal__save");

      assert.notStrictEqual(
        this.modal.activeModal,
        null,
        "keeps the dialog open"
      );
      assert.strictEqual(this.refreshes, 1, "refreshes the case");
      assert
        .dom(".atcp-case-edit-technical-modal__errors")
        .includesText("Case is closed");
    });

    test("closes and notifies the parent on a 403", async function (assert) {
      pretender.put("/atcp/cases/1.json", () =>
        response(403, { errors: ["Case is closed"] })
      );

      await renderModal(this);
      await fillIn(`${field("symptom")} textarea`, "Updated fan noise.");
      await click(".atcp-case-edit-technical-modal__save");

      assert.strictEqual(this.modal.activeModal, null, "closes the dialog");
      assert.strictEqual(this.noLongerEditable, 1, "notifies the parent");
      assert.strictEqual(this.saved, 0);
    });

    test("confirms before discarding changes on cancel", async function (assert) {
      await renderModal(this);
      await fillIn(`${field("symptom")} textarea`, "Updated fan noise.");

      this.discard = false;
      await click(".atcp-case-edit-technical-modal__cancel");

      assert.notStrictEqual(
        this.modal.activeModal,
        null,
        "keeps the dialog open"
      );
      assert.true(
        this.dialogParams.message.includes("Discard your changes"),
        "asks for confirmation"
      );

      this.discard = true;
      await click(".atcp-case-edit-technical-modal__cancel");

      assert.strictEqual(this.modal.activeModal, null, "discards the changes");
    });

    test("confirms before closing with unsaved changes", async function (assert) {
      await renderModal(this);
      await fillIn(`${field("symptom")} textarea`, "Updated fan noise.");

      this.discard = false;
      await click(".modal-close");

      assert.notStrictEqual(
        this.modal.activeModal,
        null,
        "keeps the dialog open"
      );

      this.discard = true;
      await click(".modal-close");

      assert.strictEqual(this.modal.activeModal, null, "closes the dialog");
    });

    test("cancel closes without confirmation when nothing changed", async function (assert) {
      await renderModal(this);
      await click(".atcp-case-edit-technical-modal__cancel");

      assert.strictEqual(this.modal.activeModal, null, "closes the dialog");
      assert.strictEqual(this.dialogParams, null, "does not ask for confirmation");
    });
  }
);
