import { click, fillIn, render, settled, triggerEvent } from "@ember/test-helpers";
import { module, test } from "qunit";
import ModalContainer from "discourse/components/modal-container";
import { setupRenderingTest } from "discourse/tests/helpers/component-test";
import pretender, {
  parsePostData,
  response,
} from "discourse/tests/helpers/create-pretender";
import selectKit from "discourse/tests/helpers/select-kit-helper";
import AtcpCaseNewModal from "discourse/plugins/discourse-atcp-case/discourse/components/atcp-case/atcp-case-new-modal";

const FORM_OPTIONS = {
  case_types: ["Hardware defect", "Compatibility"],
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
    {
      name: "RND",
      users: [{ id: 9, username: "adit", name: "Adit" }],
    },
    {
      name: "Warehouse",
      users: [{ id: 10, username: "budi", name: "Budi" }],
    },
    {
      name: "Other",
      users: [{ id: 11, username: "sari", name: "Sari" }],
    },
  ],
};

const PRODUCTS = [
  { id: 11, name: "Axioo P15", sku_code: "AXIOO-P15" },
  { id: 12, name: "Axioo P17 (AXIOO-P17)", sku_code: "AXIOO-P17" },
];

let productSearchMode = "success";
let productQueries = [];

async function selectCaseType(value) {
  const select = document.querySelector(
    ".atcp-case-new-modal .form-kit__field[data-name='case_type'] select"
  );
  select.value = value;
  await triggerEvent(select, "input");
}

async function selectNativeField(name, value) {
  const select = document.querySelector(
    `.atcp-case-new-modal .form-kit__field[data-name='${name}'] select`
  );
  select.value = value;
  await triggerEvent(select, "change");
}

async function renderModal(context) {
  await render(
    <template>
      <ModalContainer />
    </template>
  );

  context.modal.show(AtcpCaseNewModal, { model: context.model });
  await settled();
}

function productChooser() {
  return selectKit(".atcp-case-new-modal .atcp-case-product-chooser");
}

async function chooseProduct(id, query = "Axioo") {
  const chooser = productChooser();

  if (!document.querySelector(".atcp-case-product-chooser.is-expanded")) {
    await chooser.expand();
  }

  await fillIn(
    ".atcp-case-new-modal .atcp-case-product-chooser .filter-input",
    query
  );
  await chooser.selectRowByValue(String(id));
}

function selectedChips() {
  return [
    ...document.querySelectorAll(
      ".atcp-case-new-modal .atcp-case-product-chooser .select-kit-header .selected-choice"
    ),
  ].map((chip) => chip.textContent.trim());
}

async function fillRequiredTextFields() {
  await fillIn(
    ".atcp-case-new-modal .form-kit__field[data-name='title'] input",
    "Battery drains quickly"
  );

  await selectCaseType("Hardware defect");

  await fillIn(
    ".atcp-case-new-modal .form-kit__field[data-name='source'] input",
    "Branch technician"
  );
  await fillIn(
    ".atcp-case-new-modal .form-kit__field[data-name='symptom'] textarea",
    "Battery drops from 100% to 20% in one hour."
  );
}

async function fillRequiredFields(productId = "11") {
  await fillRequiredTextFields();
  await chooseProduct(productId);
}

module("Integration | Component | AtcpCaseNewModal", function (hooks) {
  setupRenderingTest(hooks, { stubRouter: true });

  hooks.beforeEach(function () {
    this.model = { formOptions: FORM_OPTIONS, picGroups: PIC_GROUPS };
    this.modal = this.owner.lookup("service:modal");
    this.router = this.owner.lookup("service:router");
    this.transitionedTo = null;
    this.router.transitionTo = (route, id) => {
      this.transitionedTo = { route, id };
    };

    productSearchMode = "success";
    productQueries = [];

    pretender.get("/atcp/products/search.json", (request) => {
      productQueries.push(request.queryParams.q);

      if (productSearchMode === "failure") {
        return response(500, { errors: ["Product search unavailable"] });
      }

      return response({ products: PRODUCTS });
    });
  });

  hooks.afterEach(function () {
    if (this.modal.activeModal) {
      this.modal.close();
    }
  });

  test("renders the fields and defaults in order", async function (assert) {
    await renderModal(this);

    assert.dom(".d-modal__title-text").hasText("New Case");
    assert
      .dom(".atcp-case-new-modal .form-kit__field")
      .exists({ count: 7 }, "renders all seven fields");
    assert.deepEqual(
      [
        ...document.querySelectorAll(
          ".atcp-case-new-modal .form-kit__container-title"
        ),
      ].map((label) => label.querySelector("span").textContent.trim()),
      ["Title", "Type", "Severity", "Source", "Product", "Symptom", "PIC"],
      "renders every field label in order"
    );
    assert
      .dom(".atcp-case-new-modal__optional .form-kit__section-title")
      .hasText("Optional");
    assert
      .dom(".atcp-case-new-modal__description")
      .includesText(
        "Fill in the required fields. The optional details below can also be added later."
      );

    assert
      .dom(".atcp-case-new-modal .form-kit__field[data-name='case_type'] option:checked")
      .hasText("Select a type");
    assert
      .dom(".atcp-case-new-modal .form-kit__field[data-name='severity'] select")
      .hasValue("Medium");
    assert
      .dom(".atcp-case-new-modal .atcp-case-product-chooser .filter-input")
      .hasAttribute("placeholder", "Search products by name or SKU");

    assert.strictEqual(
      document.activeElement,
      document.querySelector(
        ".atcp-case-new-modal .form-kit__field[data-name='title'] input"
      ),
      "title receives initial focus"
    );
  });

  test("renders PIC groups with Unassigned first", async function (assert) {
    await renderModal(this);

    const select = document.querySelector(
      ".atcp-case-new-modal .form-kit__field[data-name='assignee_id'] select"
    );
    const groups = [...select.querySelectorAll("optgroup")];

    assert
      .dom(select.querySelector("option"))
      .hasText("Unassigned", "first option is Unassigned");
    assert.deepEqual(
      groups.map((group) => group.getAttribute("label")),
      ["Technical Support", "Production", "RND", "Warehouse", "Other"],
      "preserves the group titles"
    );
    assert.deepEqual(
      groups.flatMap((group) =>
        [...group.querySelectorAll("option")].map((option) =>
          option.textContent.trim()
        )
      ),
      ["Jordan", "rina", "Adit", "Budi", "Sari"],
      "uses the name or falls back to the username"
    );
  });

  test("renders only Unassigned when PIC groups fail to load", async function (assert) {
    this.model = {
      formOptions: FORM_OPTIONS,
      picGroups: { groups: [] },
    };
    await renderModal(this);

    const select = document.querySelector(
      ".atcp-case-new-modal .form-kit__field[data-name='assignee_id'] select"
    );

    assert
      .dom(
        ".atcp-case-new-modal .form-kit__field[data-name='assignee_id'] option"
      )
      .exists({ count: 1 });
    assert
      .dom(
        ".atcp-case-new-modal .form-kit__field[data-name='assignee_id'] optgroup"
      )
      .doesNotExist();
    assert.dom(select.querySelector("option")).hasText("Unassigned");
  });

  test("requires at least one product before making a request", async function (assert) {
    let requests = 0;
    pretender.post("/atcp/cases.json", () => {
      requests += 1;
      return response({ case: { id: 1 } });
    });

    await renderModal(this);
    await fillRequiredTextFields();
    await click(".atcp-case-new-modal__submit");

    assert.strictEqual(requests, 0, "invalid form is not submitted");
    assert
      .dom(".atcp-case-new-modal .form-kit__field[data-name='product_ids'] .form-kit__errors")
      .hasText("At least one product is required");
    assert
      .dom(".atcp-case-new-modal .form-kit__field[data-name='title'] .form-kit__errors")
      .doesNotExist("filled text fields are valid");
  });

  test("searches products, keeps chips, removes one, and submits product_ids", async function (assert) {
    let submitted;

    pretender.post("/atcp/cases.json", (request) => {
      submitted = parsePostData(request.requestBody);
      return response({ case: { id: 123 } });
    });

    await renderModal(this);
    await fillRequiredTextFields();
    await productChooser().expand();
    await fillIn(
      ".atcp-case-new-modal .atcp-case-product-chooser .filter-input",
      "Axioo"
    );

    assert.deepEqual(productQueries, ["Axioo"], "searches with the typed term");
    assert.deepEqual(
      [...document.querySelectorAll(
        ".atcp-case-new-modal .atcp-case-product-chooser .select-kit-row"
      )].map((row) => row.textContent.trim()),
      ["Axioo P15 (AXIOO-P15)", "Axioo P17 (AXIOO-P17)"],
      "rows show each SKU exactly once"
    );

    await productChooser().selectRowByValue("11");
    assert.deepEqual(selectedChips(), ["Axioo P15 (AXIOO-P15)"]);

    await chooseProduct("12", "P17");
    assert.deepEqual(
      selectedChips(),
      ["Axioo P15 (AXIOO-P15)", "Axioo P17 (AXIOO-P17)"],
      "previous selection is kept after the search changes"
    );

    await click(
      ".atcp-case-new-modal .atcp-case-product-chooser .select-kit-header .selected-choice[data-value='11']"
    );
    assert.deepEqual(selectedChips(), ["Axioo P17 (AXIOO-P17)"]);

    await click(".atcp-case-new-modal__submit");

    assert.deepEqual(
      submitted["product_ids[]"],
      ["12"],
      "sends the remaining product id"
    );
  });

  test("a failed product search offers no results without throwing", async function (assert) {
    productSearchMode = "failure";

    await renderModal(this);
    await productChooser().expand();
    await fillIn(
      ".atcp-case-new-modal .atcp-case-product-chooser .filter-input",
      "unknown"
    );

    assert.deepEqual(productQueries, ["unknown"]);
    assert
      .dom(".atcp-case-new-modal .atcp-case-product-chooser .no-content")
      .hasText("No matches found");
    assert.dom(".atcp-case-new-modal__errors").doesNotExist();
  });

  test("submits the payload, closes, and opens the created case", async function (assert) {
    let submitted;

    pretender.post("/atcp/cases.json", (request) => {
      submitted = parsePostData(request.requestBody);
      return response({ case: { id: 123 } });
    });

    await renderModal(this);
    await fillRequiredFields();
    await click(".atcp-case-new-modal__submit");

    assert.deepEqual(
      submitted,
      {
        title: "Battery drains quickly",
        case_type: "Hardware defect",
        severity: "Medium",
        source: "Branch technician",
        symptom: "Battery drops from 100% to 20% in one hour.",
        "product_ids[]": ["11"],
      },
      "sends the required fields only"
    );
    assert.strictEqual(this.modal.activeModal, null, "closes the dialog");
    assert.deepEqual(
      this.transitionedTo,
      { route: "atcp-cases.show", id: 123 },
      "opens the created case"
    );
  });

  test("sends the optional PIC field when filled", async function (assert) {
    let submitted;

    pretender.post("/atcp/cases.json", (request) => {
      submitted = parsePostData(request.requestBody);
      return response({ case: { id: 124 } });
    });

    await renderModal(this);
    await fillRequiredFields();
    await selectNativeField("assignee_id", "5");
    await click(".atcp-case-new-modal__submit");

    assert.deepEqual(
      submitted,
      {
        title: "Battery drains quickly",
        case_type: "Hardware defect",
        severity: "Medium",
        source: "Branch technician",
        symptom: "Battery drops from 100% to 20% in one hour.",
        "product_ids[]": ["11"],
        assignee_id: "5",
      },
      "sends the selected optional value"
    );
  });

  test("shows field errors inline and unknown or base errors in an alert", async function (assert) {
    pretender.post("/atcp/cases.json", () =>
      response(422, {
        errors: {
          title: ["Title is already used"],
          product_ids: ["Products are required"],
          bios_version: ["BIOS version is invalid"],
          base: ["Unable to save this case"],
        },
      })
    );

    await renderModal(this);
    await fillRequiredFields();
    await click(".atcp-case-new-modal__submit");

    assert.notStrictEqual(
      this.modal.activeModal,
      null,
      "keeps the dialog open"
    );
    assert
      .dom(".atcp-case-new-modal .form-kit__field[data-name='title'] .form-kit__errors")
      .hasText("Title is already used");
    assert
      .dom(".atcp-case-new-modal .form-kit__field[data-name='product_ids'] .form-kit__errors")
      .hasText("Products are required");

    const alert = document.querySelector(".atcp-case-new-modal__errors");
    assert.strictEqual(alert.getAttribute("role"), "alert");
    assert.true(alert.textContent.includes("Unable to save this case"));
    assert.true(alert.textContent.includes("BIOS version: BIOS version is invalid"));
    assert.false(alert.textContent.includes("Title is already used"));
    assert.false(alert.textContent.includes("Products are required"));
  });

  test("shows a 422 assignee error in the PIC field", async function (assert) {
    pretender.post("/atcp/cases.json", () =>
      response(422, {
        errors: {
          assignee_id: ["Assignee must be an internal member"],
        },
      })
    );

    await renderModal(this);
    await fillRequiredFields();
    await selectNativeField("assignee_id", "5");
    await click(".atcp-case-new-modal__submit");

    assert
      .dom(".atcp-case-new-modal .form-kit__field[data-name='assignee_id'] .form-kit__errors")
      .hasText("Assignee must be an internal member");
    assert
      .dom(".atcp-case-new-modal__errors")
      .doesNotExist("known field errors are not repeated in the alert");
  });

  test("passes non-422 errors to popupAjaxError", async function (assert) {
    const dialog = this.owner.lookup("service:dialog");
    dialog.alert = (message) => {
      this.alertMessage = message;
    };

    pretender.post("/atcp/cases.json", () =>
      response(500, { errors: ["Server unavailable"] })
    );

    await renderModal(this);
    await fillRequiredFields();
    await click(".atcp-case-new-modal__submit");

    assert.true(
      String(this.alertMessage).includes("Server unavailable"),
      "shows the ajax error dialog"
    );
    assert.notStrictEqual(
      this.modal.activeModal,
      null,
      "keeps the dialog open"
    );
  });

  test("prevents double submission while the request is pending", async function (assert) {
    let requests = 0;
    let releaseRequest;
    let requestStarted;
    const started = new Promise((resolve) => (requestStarted = resolve));

    pretender.post("/atcp/cases.json", async () => {
      requests += 1;
      requestStarted();
      await new Promise((resolve) => (releaseRequest = resolve));
      return response({ case: { id: 125 } });
    });

    await renderModal(this);
    await fillRequiredFields();

    const firstClick = click(".atcp-case-new-modal__submit");
    await started;

    assert
      .dom(".atcp-case-new-modal__submit")
      .isDisabled("submit is disabled while saving");

    const form = document.querySelector(".atcp-case-new-modal form");
    form.dispatchEvent(
      new Event("submit", { bubbles: true, cancelable: true })
    );

    releaseRequest();
    await firstClick;

    assert.strictEqual(requests, 1, "only one request is sent");
  });

  test("cancel closes without submitting", async function (assert) {
    let requests = 0;
    pretender.post("/atcp/cases.json", () => {
      requests += 1;
      return response({ case: { id: 126 } });
    });

    await renderModal(this);
    await click(".atcp-case-new-modal__cancel");

    assert.strictEqual(this.modal.activeModal, null, "closes the dialog");
    assert.strictEqual(requests, 0, "does not submit");
  });
});
