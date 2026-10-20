import { module, test } from "qunit";
import {
  buildCaseListParams,
  caseListErrorMessage,
  caseSeverityKey,
  caseStatusKey,
  caseStatusPills,
  DEFAULT_CASE_PAGE,
  DEFAULT_CASE_STATUS,
  emptyCaseList,
  hasActiveCaseFilters,
} from "discourse/plugins/discourse-atcp-case/discourse/lib/atcp-case-list-params";

module("Unit | Lib | atcp-case-list-params", function () {
  test("buildCaseListParams omits default status and page", function (assert) {
    assert.deepEqual(
      buildCaseListParams({ status: DEFAULT_CASE_STATUS, page: DEFAULT_CASE_PAGE }),
      {},
      "default filters produce no request params"
    );
  });

  test("buildCaseListParams keeps non-default filters", function (assert) {
    assert.deepEqual(
      buildCaseListParams({
        status: "Open",
        q: "battery",
        severity: "High",
        case_type: "Hardware",
        product_id: 3,
        assignee_id: "7",
        date_from: "2026-08-01",
        date_to: "2026-08-31",
        page: 2,
      }),
      {
        q: "battery",
        severity: "High",
        case_type: "Hardware",
        product_id: "3",
        assignee_id: "7",
        date_from: "2026-08-01",
        date_to: "2026-08-31",
        status: "Open",
        page: 2,
      },
      "non-default filters are forwarded"
    );
  });

  test("buildCaseListParams drops blank filters and invalid pages", function (assert) {
    assert.deepEqual(
      buildCaseListParams({ q: "  ", severity: null, case_type: undefined }),
      {},
      "blank and nil filters are dropped"
    );

    assert.deepEqual(
      buildCaseListParams({ page: "abc" }),
      {},
      "non numeric page falls back to the default"
    );

    assert.deepEqual(
      buildCaseListParams({ page: "0" }),
      {},
      "page below the default is dropped"
    );
  });

  test("hasActiveCaseFilters detects every non-default filter", function (assert) {
    assert.false(hasActiveCaseFilters({ status: DEFAULT_CASE_STATUS }), "default status alone is not a filter");
    assert.true(hasActiveCaseFilters({ status: "Closed" }), "non-default status is a filter");
    assert.true(hasActiveCaseFilters({ q: "battery" }), "search term is a filter");
    assert.true(hasActiveCaseFilters({ product_id: "3" }), "product is a filter");
    assert.true(hasActiveCaseFilters({ date_from: "2026-08-01" }), "date range is a filter");
  });

  test("caseStatusKey and caseSeverityKey normalize labels", function (assert) {
    assert.strictEqual(caseStatusKey("In Progress"), "in-progress");
    assert.strictEqual(caseStatusKey("Solution Found"), "solution-found");
    assert.strictEqual(caseStatusKey(null), "");
    assert.strictEqual(caseSeverityKey("Critical"), "critical");
    assert.strictEqual(caseSeverityKey(undefined), "");
  });

  test("caseStatusPills maps status counts", function (assert) {
    const pills = caseStatusPills({
      active: 9,
      Open: 2,
      "In Progress": 3,
      "On Hold": 1,
      "Solution Found": 2,
      Closed: 4,
    });

    assert.deepEqual(
      pills.map((pill) => pill.key),
      ["active", "open", "in-progress", "on-hold", "solution-found", "closed"],
      "pills follow the canonical order"
    );
    assert.deepEqual(
      pills.map((pill) => pill.count),
      [9, 2, 3, 1, 2, 4],
      "counts come from status_counts"
    );
    assert.deepEqual(
      caseStatusPills({}).map((pill) => pill.count),
      [0, 0, 0, 0, 0, 0],
      "missing counts fall back to zero"
    );
  });

  test("emptyCaseList returns a safe list shape", function (assert) {
    assert.deepEqual(emptyCaseList(), {
      cases: [],
      status_counts: { active: 0 },
      total_count: 0,
      page: 1,
      per_page: 20,
      total_pages: 1,
    });
  });

  test("caseListErrorMessage prefers the server message", function (assert) {
    assert.strictEqual(
      caseListErrorMessage({
        jqXHR: { responseJSON: { errors: ["Invalid filter"] } },
      }),
      "Invalid filter"
    );
    assert.strictEqual(caseListErrorMessage({}), null);
  });
});
