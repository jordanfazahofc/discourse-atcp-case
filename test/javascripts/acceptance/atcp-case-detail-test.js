import { click, currentURL, settled, visit } from "@ember/test-helpers";
import { test } from "qunit";
import { acceptance } from "discourse/tests/helpers/qunit-helpers";
import { DETAIL_CASE } from "../fixtures/atcp-case-detail";

const CASE_ROWS = [
  {
    id: 1,
    case_number: "CASE-2026-0001",
    title: "Fan noise on boot",
    products: [{ id: 11, name: "Axioo P15", sku: "AXIOO-P15" }],
    severity: "Critical",
    status: "Closed",
    assignee: null,
    aging_days: 5,
    waiting: null,
  },
  {
    id: 2,
    case_number: "CASE-2026-0002",
    title: "Keyboard backlight flicker",
    products: [],
    severity: "High",
    status: "Open",
    assignee: null,
    aging_days: 1,
    waiting: null,
  },
];

let detailRequests = [];
let missingCaseId = null;

function caseFor(id) {
  return {
    ...DETAIL_CASE,
    id: Number(id),
    case_number: `CASE-2026-${String(id).padStart(4, "0")}`,
    title: id === "2" ? "Keyboard backlight flicker" : DETAIL_CASE.title,
  };
}

acceptance("ATCP | Case detail", function (needs) {
  needs.user({ atcp_internal_access: true });
  needs.settings({ atcp_case_enabled: true });

  needs.hooks.beforeEach(function () {
    detailRequests = [];
    missingCaseId = null;
  });

  needs.pretender((server, helper) => {
    server.get("/atcp/cases.json", () =>
      helper.response({
        cases: CASE_ROWS,
        status_counts: {
          active: 1,
          Open: 1,
          "In Progress": 0,
          "On Hold": 0,
          "Solution Found": 0,
          Closed: 1,
        },
        total_count: 2,
        page: 1,
        per_page: 20,
        total_pages: 1,
      })
    );

    server.get("/atcp/cases/form_options.json", () =>
      helper.response({
        case_types: ["Hardware"],
        severities: ["Low", "Medium", "High", "Critical"],
        statuses: ["Open", "Closed"],
        close_reasons: ["Resolved"],
        frequencies: ["Always"],
        branches: [],
      })
    );

    server.get("/atcp/cases/pic_candidates.json", () =>
      helper.response({ groups: [] })
    );

    server.get("/atcp/cases/:case_id.json", (request) => {
      const id = request.url.match(/\/atcp\/cases\/([^/.?]+)\.json/)?.[1];
      detailRequests.push(id);

      if (id === missingCaseId) {
        return helper.response(404, { errors: ["Case not found"] });
      }

      return helper.response({ case: caseFor(id) });
    });
  });

  test("renders the detail and switches tabs without refetching", async function (assert) {
    await visit("/internal/cases/1");

    assert
      .dom(".atcp-case-detail__title")
      .hasText("CASE-2026-0001 · Fan noise on boot");
    assert.strictEqual(detailRequests.length, 1);
    assert.dom(".atcp-case-detail__update-body").exists();

    await click(".atcp-case-detail__tab[data-tab='technical']");

    assert.strictEqual(currentURL(), "/internal/cases/1?tab=technical");
    assert
      .dom(".atcp-case-detail__tab[data-tab='technical']")
      .hasAttribute("aria-selected", "true");
    assert.dom('[data-field="frequency"]').exists();
    assert.strictEqual(
      detailRequests.length,
      1,
      "changing tabs does not refetch the case"
    );

    await click(".atcp-case-detail__tab[data-tab='attachments']");

    assert.strictEqual(currentURL(), "/internal/cases/1?tab=attachments");
    assert.dom(".atcp-case-detail__attachment-row").exists({ count: 2 });

    await click(".atcp-case-detail__tab[data-tab='progress']");

    assert.strictEqual(
      currentURL(),
      "/internal/cases/1",
      "the default tab is omitted from the URL"
    );
    assert.strictEqual(detailRequests.length, 1);
  });

  test("normalizes an unknown tab back to progress", async function (assert) {
    await visit("/internal/cases/1?tab=bogus");

    assert
      .dom(".atcp-case-detail__tab[data-tab='progress']")
      .hasAttribute("aria-selected", "true");
    assert.dom(".atcp-case-detail__update-body").exists();
    assert.strictEqual(currentURL(), "/internal/cases/1");
    assert.deepEqual(detailRequests, ["1"], "normalizing does not refetch");
  });

  test("omits the default tab when it is present in the URL", async function (assert) {
    await visit("/internal/cases/1?tab=progress");

    assert.strictEqual(currentURL(), "/internal/cases/1");
    assert
      .dom(".atcp-case-detail__tab[data-tab='progress']")
      .hasAttribute("aria-selected", "true");
    assert.deepEqual(detailRequests, ["1"], "normalizing does not refetch");
  });

  test("shows the not found state for a missing case", async function (assert) {
    missingCaseId = "404";

    await visit("/internal/cases/404");

    assert.dom(".atcp-case-detail__not-found h1").hasText("Case not found");
    assert.dom(".atcp-case-detail__tabs").doesNotExist();
    assert
      .dom(".atcp-case-detail__back")
      .hasAttribute("href", "/internal/cases");
    assert.deepEqual(detailRequests, ["404"]);
  });

  test("shows the not found state for a non-numeric case id", async function (assert) {
    await visit("/internal/cases");

    await this.owner
      .lookup("service:router")
      .transitionTo("atcp-cases.show", "not-a-number");
    await settled();

    assert.dom(".atcp-case-detail__not-found h1").hasText("Case not found");
    assert.deepEqual(detailRequests, [], "no request is made");
  });

  test("reloads when switching cases and resets the tab", async function (assert) {
    await visit("/internal/cases/1?tab=technical");

    assert
      .dom(".atcp-case-detail__tab[data-tab='technical']")
      .hasAttribute("aria-selected", "true");

    await this.owner
      .lookup("service:router")
      .transitionTo("atcp-cases.show", "2");
    await settled();

    assert.strictEqual(currentURL(), "/internal/cases/2");
    assert
      .dom(".atcp-case-detail__title")
      .hasText("CASE-2026-0002 · Keyboard backlight flicker");
    assert
      .dom(".atcp-case-detail__tab[data-tab='progress']")
      .hasAttribute("aria-selected", "true");
    assert.deepEqual(detailRequests, ["1", "2"], "the new case is fetched");
  });
});
