import { hash } from "@ember/helper";
import { render, triggerEvent } from "@ember/test-helpers";
import { module, test } from "qunit";
import { setupRenderingTest } from "discourse/tests/helpers/component-test";
import AtcpCaseList from "discourse/plugins/discourse-atcp-case/discourse/components/atcp-case/atcp-case-list";

const LIST = {
  cases: [
    {
      id: 1,
      case_number: "CASE-2026-0001",
      title: "Battery drains quickly",
      products: [{ id: 1, name: "Axioo P15", sku: "AXIOO-P15" }],
      severity: "High",
      status: "Open",
      assignee: { id: 5, username: "jordan", name: "Jordan" },
      aging_days: 3,
      waiting: null,
    },
  ],
  status_counts: {
    active: 1,
    Open: 1,
    "In Progress": 0,
    "On Hold": 0,
    "Solution Found": 0,
    Closed: 0,
  },
  total_count: 1,
  page: 1,
  per_page: 20,
  total_pages: 1,
};

const FORM_OPTIONS = {
  case_types: ["Hardware defect", "Compatibility"],
  severities: ["Low", "Medium", "High", "Critical"],
  statuses: ["Open", "In Progress", "On Hold", "Solution Found", "Closed"],
};

const PIC_GROUPS = {
  groups: [
    {
      name: "IT Clinic",
      users: [{ id: 5, username: "jordan", name: "Jordan" }],
    },
  ],
};

function defaultFilters(overrides = {}) {
  return {
    status: "active",
    q: null,
    severity: null,
    case_type: null,
    product_id: null,
    assignee_id: null,
    date_from: null,
    date_to: null,
    ...overrides,
  };
}

module("Integration | Component | AtcpCaseList", function (hooks) {
  setupRenderingTest(hooks);

  hooks.beforeEach(function () {
    this.openedCaseIds = [];
    this.onOpenCase = (id) => this.openedCaseIds.push(id);
    this.list = LIST;
    this.filters = defaultFilters();
    this.formOptions = FORM_OPTIONS;
    this.picGroups = PIC_GROUPS;
    this.preventDefault = (event) => event.preventDefault();
    document.addEventListener("click", this.preventDefault);
  });

  hooks.afterEach(function () {
    document.removeEventListener("click", this.preventDefault);
  });

  async function renderList(context) {
    await render(
      <template>
        <AtcpCaseList
          @list={{context.list}}
          @formOptions={{context.formOptions}}
          @picGroups={{context.picGroups}}
          @filters={{context.filters}}
          @onOpenCase={{context.onOpenCase}}
          @options={{hash}}
        />
      </template>
    );
  }

  test("opens the case from a link exactly once", async function (assert) {
    await renderList(this);

    await triggerEvent(".atcp-case-list__link", "click", { button: 0 });

    assert.deepEqual(this.openedCaseIds, [1]);
  });

  test("opens the case when clicking a non-link cell", async function (assert) {
    await renderList(this);

    await triggerEvent(".atcp-case-list__case-title", "click", { button: 0 });

    assert.deepEqual(this.openedCaseIds, [1]);
  });

  test("leaves modified or non-primary link clicks to the browser", async function (assert) {
    await renderList(this);

    for (const modifier of ["ctrlKey", "metaKey", "shiftKey"]) {
      await triggerEvent(".atcp-case-list__link", "click", {
        button: 0,
        [modifier]: true,
      });
    }
    await triggerEvent(".atcp-case-list__link", "click", { button: 1 });

    assert.deepEqual(this.openedCaseIds, [], "no programmatic navigation");
  });

  test("shows a temporary label for an assignee outside the candidates", async function (assert) {
    this.filters = defaultFilters({ assignee_id: "99" });
    await renderList(this);

    assert
      .dom(".atcp-case-list__pic .select-kit-header")
      .hasText("User #99");
  });
});
