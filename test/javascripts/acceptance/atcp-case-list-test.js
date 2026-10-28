import {
  click,
  currentURL,
  fillIn,
  triggerEvent,
  triggerKeyEvent,
  visit,
} from "@ember/test-helpers";
import { test } from "qunit";
import { parsePostData } from "discourse/tests/helpers/create-pretender";
import { acceptance } from "discourse/tests/helpers/qunit-helpers";
import selectKit from "discourse/tests/helpers/select-kit-helper";
import { DETAIL_CASE } from "../fixtures/atcp-case-detail";

const FORM_OPTIONS = {
  case_types: ["Hardware", "Software"],
  severities: ["Low", "Medium", "High", "Critical"],
  statuses: ["Open", "In Progress", "On Hold", "Solution Found", "Closed"],
  close_reasons: ["Resolved"],
  frequencies: ["Always"],
};

const PRODUCTS = [
  { id: 11, name: "Axioo P15", sku_code: "AXIOO-P15" },
  { id: 12, name: "Axioo P17", sku_code: "AXIOO-P17" },
];

const PIC_CANDIDATES = {
  groups: [
    {
      name: "IT Clinic",
      users: [{ id: 5, username: "jordan", name: "Jordan" }],
    },
  ],
};

const STATUS_COUNTS = {
  active: 4,
  Open: 2,
  "In Progress": 1,
  "On Hold": 0,
  "Solution Found": 1,
  Closed: 3,
};

const CASE_ROWS = [
  {
    id: 1,
    case_number: "CASE-2026-0001",
    title: "Battery drains quickly",
    products: [
      { id: 1, name: "Axioo P15", sku: "AXIOO-P15" },
      { id: 2, name: "Axioo P17", sku: "AXIOO-P17" },
    ],
    severity: "High",
    status: "Open",
    assignee: { id: 5, username: "jordan", name: "Jordan" },
    aging_days: 3,
    waiting: null,
  },
  {
    id: 2,
    case_number: "CASE-2026-0002",
    title: "Fan noise on boot",
    products: [{ id: 1, name: "Axioo P15", sku: "AXIOO-P15" }],
    severity: "Critical",
    status: "In Progress",
    assignee: null,
    aging_days: 1,
    waiting: { label: "Waiting for unit", days: 2 },
  },
];

const PAGE_TWO_ROW = {
  id: 3,
  case_number: "CASE-2026-0003",
  title: "Second page case",
  products: [{ id: 2, name: "Axioo P17", sku: "AXIOO-P17" }],
  severity: "Low",
  status: "Closed",
  assignee: { id: 5, username: "jordan", name: "Jordan" },
  aging_days: 10,
  waiting: null,
};

function listResponse(request) {
  const page = Number(request.queryParams.page || 1);
  const empty = mode === "empty";

  return {
    cases: empty ? [] : page === 2 ? [PAGE_TWO_ROW] : CASE_ROWS,
    status_counts: empty
      ? {
          active: 0,
          Open: 0,
          "In Progress": 0,
          "On Hold": 0,
          "Solution Found": 0,
          Closed: 0,
        }
      : STATUS_COUNTS,
    total_count: empty ? 0 : 4,
    page,
    per_page: 20,
    total_pages: empty ? 1 : 2,
  };
}

let mode = "default";
let caseRequests = [];
let holdListRequest = false;
let listRequestStarted = null;
let releaseListRequest = null;
let formOptionsCalls = 0;
let failFormOptionsOnce = false;
let submittedCreate = null;
let productQueries = [];

function pillLabels() {
  return [...document.querySelectorAll(".atcp-case-list__pill")].map((pill) =>
    pill.textContent.replace(/\s+/g, " ").trim()
  );
}

function pillByLabel(label) {
  return [...document.querySelectorAll(".atcp-case-list__pill")].find(
    (pill) =>
      pill
        .querySelector(".atcp-case-list__pill-label")
        ?.textContent.trim() === label
  );
}

acceptance("ATCP | Case list", function (needs) {
  needs.user({ atcp_internal_access: true });
  needs.settings({ atcp_case_enabled: true });

  needs.hooks.beforeEach(function () {
    mode = "default";
    caseRequests = [];
    holdListRequest = false;
    listRequestStarted = null;
    releaseListRequest = null;
    formOptionsCalls = 0;
    failFormOptionsOnce = false;
    submittedCreate = null;
    productQueries = [];
  });

  needs.pretender((server, helper) => {
    server.get("/atcp/cases/form_options.json", () => {
      formOptionsCalls++;

      if (failFormOptionsOnce) {
        failFormOptionsOnce = false;
        return helper.response(500, { errors: ["form options unavailable"] });
      }

      return helper.response(FORM_OPTIONS);
    });

    server.get("/atcp/cases/pic_candidates.json", () =>
      helper.response(PIC_CANDIDATES)
    );

    server.get("/atcp/cases/:case_id.json", (request) => {
      const id = request.url.match(/\/atcp\/cases\/([^/.?]+)\.json/)?.[1];

      return helper.response({
        case: {
          ...DETAIL_CASE,
          id: Number(id),
          case_number: `CASE-2026-${String(id).padStart(4, "0")}`,
        },
      });
    });

    server.get("/atcp/products/search.json", (request) => {
      productQueries.push(request.queryParams.q);
      return helper.response({ products: PRODUCTS });
    });

    server.post("/atcp/cases.json", (request) => {
      submittedCreate = parsePostData(request.requestBody);
      return helper.response(201, { case: { id: 123 } });
    });

    server.get("/atcp/cases.json", async (request) => {
      caseRequests.push(request.queryParams);

      if (holdListRequest) {
        holdListRequest = false;
        listRequestStarted?.();
        await new Promise((resolve) => (releaseListRequest = resolve));
      }

      if (mode === "invalid") {
        return helper.response(422, { errors: ["Invalid filter"] });
      }

      return helper.response(listResponse(request));
    });
  });

  test("renders the case list with pills, rows, badges, and pagination", async function (assert) {
    await visit("/internal/cases");

    assert.dom(".atcp-case-list__title").hasText("Case Management");
    assert
      .dom(".atcp-case-list__header .atcp-case-list__new")
      .hasText("New Case");

    assert.deepEqual(
      pillLabels(),
      [
        "Active 4",
        "Open 2",
        "In Progress 1",
        "On Hold 0",
        "Solution Found 1",
        "Closed 3",
      ],
      "shows counted status pills in canonical order"
    );

    assert.dom(".atcp-case-list__row").exists({ count: 2 });

    assert
      .dom(".atcp-case-list__row:first-child .atcp-case-list__link")
      .hasText("CASE-2026-0001");
    assert
      .dom(".atcp-case-list__row:first-child .atcp-case-list__case-title")
      .hasText("Battery drains quickly");
    assert
      .dom(".atcp-case-list__row:first-child .atcp-case-list__products")
      .hasText("Axioo P15 +1");
    assert
      .dom(".atcp-case-list__row:first-child .atcp-case-list__products")
      .hasAttribute("title", "Axioo P15, Axioo P17");
    assert
      .dom(".atcp-case-list__row:first-child .atcp-case-severity--high")
      .hasText("High");
    assert
      .dom(".atcp-case-list__row:first-child .atcp-case-status--open")
      .hasText("Open");
    assert
      .dom(".atcp-case-list__row:first-child .atcp-case-list__assignee")
      .hasText("Jordan");
    assert
      .dom(".atcp-case-list__row:first-child .atcp-case-list__aging")
      .hasText("3 days");
    assert
      .dom(".atcp-case-list__row:last-child .atcp-case-list__waiting")
      .hasText("Waiting for unit · 2d");
    assert
      .dom(".atcp-case-list__row:last-child .atcp-case-list__assignee")
      .hasText("-");

    assert.dom(".atcp-case-list__total").hasText("4 cases");
    assert.dom(".atcp-case-list__page-info").hasText("Page 1 of 2");
    assert.dom(".atcp-case-list__page-prev").isDisabled();
    assert.dom(".atcp-case-list__page-next").isNotDisabled();
    assert.dom(".atcp-case-list__error").doesNotExist();
  });

  test("opens New Case from the header, closes with Escape, and restores focus", async function (assert) {
    await visit("/internal/cases");

    const newCaseButton = document.querySelector(".atcp-case-list__new");
    newCaseButton.focus();
    await click(newCaseButton);

    assert.dom(".atcp-case-new-modal").exists("opens the dialog");
    assert.dom(".d-modal__title-text").hasText("New Case");
    assert.strictEqual(
      document.activeElement,
      document.querySelector(
        ".atcp-case-new-modal .form-kit__field[data-name='title'] input"
      ),
      "title receives initial focus"
    );

    await triggerKeyEvent(document.documentElement, "keydown", "Escape");

    assert.dom(".atcp-case-new-modal").doesNotExist("Escape closes the dialog");
    assert.strictEqual(
      document.activeElement,
      newCaseButton,
      "focus returns to the New Case button"
    );
  });

  test("creates a case from the dialog and opens the new case", async function (assert) {
    await visit("/internal/cases");

    await click(".atcp-case-list__new");
    await fillIn(
      ".atcp-case-new-modal .form-kit__field[data-name='title'] input",
      "Battery drains quickly"
    );

    const caseType = document.querySelector(
      ".atcp-case-new-modal .form-kit__field[data-name='case_type'] select"
    );
    caseType.value = "Hardware";
    await triggerEvent(caseType, "input");

    await fillIn(
      ".atcp-case-new-modal .form-kit__field[data-name='source'] input",
      "Branch technician"
    );
    await fillIn(
      ".atcp-case-new-modal .form-kit__field[data-name='symptom'] textarea",
      "Battery drops from 100% to 20% in one hour."
    );

    const products = selectKit(".atcp-case-product-chooser");
    await products.expand();
    await fillIn(".atcp-case-product-chooser .filter-input", "Axioo");
    await products.selectRowByValue("11");

    assert.deepEqual(productQueries, ["Axioo"]);
    assert
      .dom(".atcp-case-product-chooser .select-kit-header")
      .hasText("Axioo P15 (AXIOO-P15)");

    const assignee = document.querySelector(
      ".atcp-case-new-modal .form-kit__field[data-name='assignee_id'] select"
    );
    assignee.value = "5";
    await triggerEvent(assignee, "change");

    await click(".atcp-case-new-modal__submit");

    assert.deepEqual(submittedCreate, {
      title: "Battery drains quickly",
      case_type: "Hardware",
      severity: "Medium",
      source: "Branch technician",
      symptom: "Battery drops from 100% to 20% in one hour.",
      "product_ids[]": ["11"],
      assignee_id: "5",
    });
    assert.strictEqual(currentURL(), "/internal/cases/123");
    assert.dom(".atcp-case-new-modal").doesNotExist("dialog is closed");
    assert
      .dom(".atcp-case-detail__back")
      .hasAttribute(
        "href",
        "/internal/cases",
        "the detail back link returns to the list"
      );
  });

  test("status pill click requests the status and resets the page", async function (assert) {
    await visit("/internal/cases?page=2&status=Closed");

    assert.dom(".atcp-case-list__page-info").hasText("Page 2 of 2");

    await click(pillByLabel("Open"));

    const lastRequest = caseRequests.at(-1);
    assert.strictEqual(lastRequest.status, "Open");
    assert.false("page" in lastRequest, "page is reset to the default");
    assert.strictEqual(currentURL(), "/internal/cases?status=Open");
    assert
      .dom(pillByLabel("Open"))
      .hasAttribute("aria-pressed", "true", "active pill is announced");
    assert.dom(".atcp-case-list__page-info").hasText("Page 1 of 2");
  });

  test("search waits for the debounce and then requests q", async function (assert) {
    await visit("/internal/cases");

    await fillIn("#atcp-case-search", "battery");

    assert.strictEqual(caseRequests.length, 2, "initial and debounced list");
    assert.strictEqual(caseRequests.at(-1).q, "battery");
    assert.strictEqual(currentURL(), "/internal/cases?q=battery");
  });

  test("Enter submits the search immediately", async function (assert) {
    await visit("/internal/cases");

    await fillIn("#atcp-case-search", "fan");
    await triggerEvent("#atcp-case-search", "keydown", { key: "Enter" });

    assert.strictEqual(caseRequests.at(-1).q, "fan");
  });

  test("selecting the severity filter sends the param and resets the page", async function (assert) {
    await visit("/internal/cases?page=2");

    const severity = selectKit(".atcp-case-list__severity");
    await severity.expand();
    await severity.selectRowByValue("High");

    const lastRequest = caseRequests.at(-1);
    assert.strictEqual(lastRequest.severity, "High");
    assert.false("page" in lastRequest, "page is reset to the default");
    assert.strictEqual(currentURL(), "/internal/cases?severity=High");
    assert.strictEqual(severity.header().value(), "High");
  });

  test("clear filters resets every query param", async function (assert) {
    await visit("/internal/cases?q=battery&severity=High&page=2");

    await click(".atcp-case-list__filter--clear .atcp-case-list__clear");

    assert.deepEqual(
      caseRequests.at(-1),
      { per_page: "20" },
      "requests the unfiltered list"
    );
    assert.strictEqual(currentURL(), "/internal/cases");
    assert.dom(".atcp-case-list__clear").doesNotExist();
  });

  test("pagination loads the next page and returns to the first", async function (assert) {
    await visit("/internal/cases");

    await click(".atcp-case-list__page-next");

    assert.strictEqual(caseRequests.at(-1).page, "2");
    assert
      .dom(".atcp-case-list__row:first-child .atcp-case-list__link")
      .hasText("CASE-2026-0003");
    assert.dom(".atcp-case-list__page-prev").isNotDisabled();
    assert.dom(".atcp-case-list__page-next").isDisabled();

    await click(".atcp-case-list__page-prev");

    assert.false("page" in caseRequests.at(-1));
    assert.dom(".atcp-case-list__page-info").hasText("Page 1 of 2");
  });

  test("restores filters from the URL on reload", async function (assert) {
    await visit("/internal/cases?status=Closed&severity=High&page=2");

    assert
      .dom(".atcp-case-list__severity .select-kit-header")
      .hasText("High");
    assert
      .dom(pillByLabel("Closed"))
      .hasAttribute("aria-pressed", "true");
    assert.dom(".atcp-case-list__page-info").hasText("Page 2 of 2");
  });

  test("opens the case detail from a row and refetches the filtered list on return", async function (assert) {
    await visit("/internal/cases?severity=High");
    const requestCount = caseRequests.length;

    await click(".atcp-case-list__row:first-child .atcp-case-list__link");
    assert.strictEqual(currentURL(), "/internal/cases/1");
    assert
      .dom(".atcp-case-detail__title")
      .includesText("CASE-2026-0001");

    await click(".atcp-case-detail__back");

    assert.strictEqual(currentURL(), "/internal/cases?severity=High");
    assert.strictEqual(
      caseRequests.length,
      requestCount + 1,
      "the filtered list is fetched again"
    );
    assert
      .dom(".atcp-case-list__severity .select-kit-header")
      .hasText("High");
  });

  test("shows the default empty state", async function (assert) {
    mode = "empty";
    await visit("/internal/cases");

    assert.dom(".atcp-case-list__empty-text").hasText("No cases yet");
    assert.dom(".atcp-case-list__clear").doesNotExist();
  });

  test("shows the filtered empty state with a clear action", async function (assert) {
    mode = "empty";
    await visit("/internal/cases?severity=High");

    assert
      .dom(".atcp-case-list__empty-text")
      .hasText("No cases match your filters");

    await click(".atcp-case-list__empty .atcp-case-list__clear");
    assert.strictEqual(currentURL(), "/internal/cases");
  });

  test("keeps the search input focused and its value across a refresh", async function (assert) {
    await visit("/internal/cases");
    const input = document.querySelector("#atcp-case-search");

    await fillIn(input, "battery");

    assert.strictEqual(
      document.activeElement,
      input,
      "search input stays focused after the refresh"
    );
    assert.strictEqual(input.value, "battery", "typed value is preserved");

    await fillIn(input, "battery2");

    assert.strictEqual(currentURL(), "/internal/cases?q=battery2");
  });

  test("keeps the current list rendered while a refresh is pending", async function (assert) {
    await visit("/internal/cases");
    assert.dom(".atcp-case-list__row").exists({ count: 2 });

    const started = new Promise((resolve) => (listRequestStarted = resolve));
    holdListRequest = true;

    const pendingClick = click(".atcp-case-list__page-next");
    await started;

    try {
      assert
        .dom(".atcp-case-list__row")
        .exists({ count: 2 }, "previous rows stay in the DOM");
      assert
        .dom(".atcp-case-list__loading")
        .doesNotExist("loading substate is not entered");
      assert.dom(".atcp-case-list--loading").exists("refresh state is exposed");
      assert
        .dom(".atcp-case-list__refreshing .spinner")
        .exists("small refresh spinner is shown");
    } finally {
      releaseListRequest();
    }

    await pendingClick;

    assert
      .dom(".atcp-case-list__row:first-child .atcp-case-list__link")
      .hasText("CASE-2026-0003");
  });

  test("cancels a pending search when leaving the list", async function (assert) {
    await visit("/internal/cases");
    const input = document.querySelector("#atcp-case-search");

    input.value = "battery";
    input.dispatchEvent(new Event("input", { bubbles: true }));

    await click(".atcp-case-list__row:first-child .atcp-case-list__link");
    await new Promise((resolve) => setTimeout(resolve, 350));

    assert.strictEqual(
      currentURL(),
      "/internal/cases/1",
      "debounced search does not run after the list is destroyed"
    );
  });

  test("retries form options after a failed load", async function (assert) {
    failFormOptionsOnce = true;
    await visit("/internal/cases");

    assert.strictEqual(formOptionsCalls, 1, "first load is attempted");
    assert.dom(".atcp-case-list__severity").exists("fallback is rendered");

    if (document.querySelector(".modal-close")) {
      await click(".modal-close");
    }

    await fillIn("#atcp-case-search", "battery");

    assert.strictEqual(formOptionsCalls, 2, "next refresh retries the lookup");
  });

  test("shows a 422 filter error inline", async function (assert) {
    mode = "invalid";
    await visit("/internal/cases?severity=High");

    assert.dom(".atcp-case-list__error").hasAttribute("role", "alert");
    assert.dom(".atcp-case-list__error").hasText("Invalid filter");
    assert.dom(".d-modal").doesNotExist("no dialog is opened");
  });
});

