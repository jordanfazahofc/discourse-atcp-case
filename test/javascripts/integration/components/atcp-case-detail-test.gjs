import { click, render } from "@ember/test-helpers";
import moment from "moment";
import { module, test } from "qunit";
import { setupRenderingTest } from "discourse/tests/helpers/component-test";
import AtcpCaseDetail from "discourse/plugins/discourse-atcp-case/discourse/components/atcp-case/detail";
import {
  DETAIL_CASE,
  emptyCase,
  openCase,
} from "../../fixtures/atcp-case-detail";

module("Integration | Component | AtcpCaseDetail", function (hooks) {
  setupRenderingTest(hooks);

  hooks.beforeEach(function () {
    this.atcpCase = DETAIL_CASE;
    this.error = null;
    this.activeTab = "progress";
    this.selectedTabs = [];
    this.onSelectTab = (tab) => this.selectedTabs.push(tab);

    this.owner
      .lookup("service:atcp-case-return-url")
      .remember("/internal/cases?severity=High");
  });

  async function renderDetail(context) {
    await render(
      <template>
        <AtcpCaseDetail
          @atcpCase={{context.atcpCase}}
          @error={{context.error}}
          @activeTab={{context.activeTab}}
          @onSelectTab={{context.onSelectTab}}
        />
      </template>
    );
  }

  test("renders the header, badges, and summary", async function (assert) {
    await renderDetail(this);

    assert
      .dom(".atcp-case-detail__back")
      .hasText("← Case Management")
      .hasAttribute("href", "/internal/cases?severity=High");
    assert
      .dom(".atcp-case-detail__title")
      .hasText("CASE-2026-0001 · Fan noise on boot");
    assert.dom(".atcp-case-severity--critical").hasText("Critical");
    assert.dom(".atcp-case-status--closed").hasText("Closed");
    assert.dom(".atcp-case-detail__type").hasText("Hardware");

    assert
      .dom('[data-field="pic"] dd')
      .hasText("Unassigned", "a missing PIC is explicit");
    assert
      .dom('[data-field="product"] dd')
      .hasText("Axioo P15 (AXIOO-P15) Legacy Axioo");
    assert
      .dom('[data-field="opened"] dd')
      .hasText(moment(DETAIL_CASE.opened_at).format("D MMM YYYY"));
    assert.dom('[data-field="aging"] dd').hasText("5 days");
    assert.dom('[data-field="source"] dd').hasText("Branch technician");
    assert
      .dom('[data-field="reporter"] dd')
      .hasText("Budi Santoso · Jakarta (JKT)");
    assert
      .dom('[data-field="closed"] dd')
      .hasText(moment(DETAIL_CASE.closed_at).format("D MMM YYYY"));
    assert.dom('[data-field="close_reason"] dd').hasText("Resolved");
    assert
      .dom(".atcp-case-detail__summary")
      .doesNotIncludeText("Affected units");
  });

  test("shows waiting state and hides closed fields for an open case", async function (assert) {
    this.atcpCase = openCase();
    await renderDetail(this);

    assert
      .dom(".atcp-case-detail__waiting")
      .hasText("Waiting for unit · 2d");
    assert.dom('[data-field="closed"]').doesNotExist();
    assert.dom('[data-field="close_reason"]').doesNotExist();
  });

  test("renders only non-empty resolution sections", async function (assert) {
    await renderDetail(this);

    assert.dom(".atcp-case-detail__section-title").exists({ count: 2 });
    assert
      .dom(".atcp-case-detail__resolution [data-field='solution']")
      .hasText("Solution Update EC firmware to version 0.9.4.");
    assert
      .dom(".atcp-case-detail__resolution [data-field='root_cause_summary']")
      .hasText("Root cause The default fan curve was too aggressive.");
    assert
      .dom(".atcp-case-detail__resolution [data-field='workaround']")
      .hasText("Workaround Set the performance mode to Quiet.");
    assert
      .dom(".atcp-case-detail__resolution [data-field='conclusion']")
      .doesNotExist("empty conclusions are hidden");
  });

  test("shows resolution for open cases when resolution text exists", async function (assert) {
    this.atcpCase = openCase({ solution: "Replace the fan assembly." });
    await renderDetail(this);

    assert.dom(".atcp-case-detail__resolution").exists();
  });

  test("hides resolution for open cases without resolution text", async function (assert) {
    this.atcpCase = emptyCase();
    await renderDetail(this);

    assert.dom(".atcp-case-detail__resolution").doesNotExist();
  });

  test("renders timeline entries, system events, edits, and attachments", async function (assert) {
    await renderDetail(this);

    assert.dom(".atcp-case-detail__update").exists({ count: 1 });
    assert.dom(".atcp-case-detail__system-update").exists({ count: 5 });

    assert.dom(".atcp-case-detail__update-author").hasText("Jordan");
    assert
      .dom(".atcp-case-detail__update-type")
      .hasText("Vendor communication");
    assert
      .dom(".atcp-case-detail__update-body")
      .hasText("Uploaded the requested evidence. Second line.");
    assert.dom(".atcp-case-detail__edited").hasText("edited");
    assert
      .dom(".atcp-case-detail__edited")
      .hasAttribute(
        "title",
        moment(DETAIL_CASE.updates[1].edited_at).format("D MMM YYYY, HH:mm")
      );
    assert
      .dom(".atcp-case-detail__update-time")
      .hasAttribute(
        "title",
        moment(DETAIL_CASE.updates[1].created_at).format("D MMM YYYY, HH:mm")
      );

    const systemText = document.querySelector(
      ".atcp-case-detail__timeline"
    ).textContent;
    assert.true(
      systemText.includes("Case closed (Resolved)"),
      "closed event uses the close reason"
    );
    assert.true(
      systemText.includes("Status changed from In Progress to Open"),
      "status event"
    );
    assert.true(
      systemText.includes("Severity changed from High to Critical"),
      "severity event"
    );
    assert.true(
      systemText.includes("Assignee changed from Unassigned to Jordan"),
      "assignee event"
    );
    assert.true(systemText.includes("Case reopened"), "reopened event");
    assert
      .dom(".atcp-case-detail__system-update-body")
      .hasText("Customer provided the requested logs.");

    assert
      .dom(".atcp-case-detail__attachment-image")
      .hasAttribute("src", "/uploads/default/original/1X/photo.png");
    assert
      .dom(".atcp-case-detail__attachment-list")
      .hasText("fan-noise.png 24 KB diagnostic-report.pdf 120 KB");
    assert
      .dom(".atcp-case-detail__attachment")
      .hasAttribute("rel", "noopener noreferrer");
    assert.dom(".atcp-case-detail__attachment-count").hasText("2 attachments");
  });

  test("renders update bodies as escaped text", async function (assert) {
    this.atcpCase = {
      ...DETAIL_CASE,
      updates: [
        {
          ...DETAIL_CASE.updates[1],
          body: "<b>Evidence</b><script>window.bad()</script>",
        },
      ],
    };
    await renderDetail(this);

    assert
      .dom(".atcp-case-detail__update-body")
      .hasText("<b>Evidence</b><script>window.bad()</script>");
    assert.dom(".atcp-case-detail__update-body b").doesNotExist();
    assert.dom(".atcp-case-detail__update-body script").doesNotExist();
  });

  test("renders tabs with ARIA state and selects a tab", async function (assert) {
    await renderDetail(this);

    assert.dom(".atcp-case-detail__tabs").hasAttribute("role", "tablist");
    assert.dom(".atcp-case-detail__tab").exists({ count: 3 });
    assert
      .dom(".atcp-case-detail__tab[data-tab='progress']")
      .hasAttribute("aria-selected", "true")
      .hasAttribute("tabindex", "0");
    assert
      .dom(".atcp-case-detail__tab[data-tab='technical']")
      .hasAttribute("aria-selected", "false")
      .hasAttribute("tabindex", "-1");
    assert
      .dom(".atcp-case-detail__tab[data-tab='attachments']")
      .hasText("Attachments (2)");

    await click(".atcp-case-detail__tab[data-tab='technical']");

    assert.deepEqual(this.selectedTabs, ["technical"]);
  });

  test("renders the technical fields and marks missing values", async function (assert) {
    this.activeTab = "technical";
    await renderDetail(this);

    assert
      .dom('[data-field="symptom"]')
      .hasText("Symptom Fan noise starts immediately after power on.");
    assert.dom('[data-field="frequency"]').hasText("Frequency Always");
    assert.dom('[data-field="reproducibility"]').hasText("Reproducibility 100%");
    assert.dom('[data-field="bios_version"]').hasText("BIOS version 1.2.3");
    assert
      .dom('[data-field="non_trigger_conditions"]')
      .hasText("Non-trigger conditions Not provided");
    assert
      .dom('[data-field="os_driver_info"]')
      .hasText("OS / driver info Not provided");
  });

  test("renders attachments tab and switches back to the update", async function (assert) {
    this.activeTab = "attachments";
    await renderDetail(this);

    assert.dom(".atcp-case-detail__attachment-row").exists({ count: 2 });
    assert
      .dom(".atcp-case-detail__attachment-row:first-child")
      .includesText("fan-noise.png");
    assert
      .dom(".atcp-case-detail__attachment-row:first-child")
      .includesText("24 KB");
    assert
      .dom(".atcp-case-detail__attachment-row:first-child")
      .includesText("Jordan");
    assert
      .dom(".atcp-case-detail__attachment-row:first-child")
      .includesText(
        moment(DETAIL_CASE.updates[1].created_at).format("D MMM YYYY")
      );
    assert
      .dom(".atcp-case-detail__attachment-thumbnail")
      .hasAttribute("src", "/uploads/default/original/1X/photo.png");

    await click(".atcp-case-detail__attachment-view");

    assert.deepEqual(this.selectedTabs, ["progress"]);
  });

  test("renders empty case states", async function (assert) {
    this.atcpCase = emptyCase();
    await renderDetail(this);

    assert
      .dom('[data-field="product"] dd')
      .hasText("No product linked");
    assert.dom('[data-field="reporter"] dd').hasText("-");
    assert.dom('[data-field="source"] dd').hasText("-");
    assert.dom(".atcp-case-detail__empty").hasText("No updates yet");
  });

  test("renders the empty attachments state", async function (assert) {
    this.atcpCase = emptyCase();
    this.activeTab = "attachments";
    await renderDetail(this);

    assert.dom(".atcp-case-detail__empty").hasText("No attachments yet");
  });

  test("tolerates invalid dates", async function (assert) {
    this.atcpCase = {
      ...DETAIL_CASE,
      opened_at: "invalid",
      closed_at: "invalid",
      updates: [
        {
          ...DETAIL_CASE.updates[1],
          created_at: "invalid",
          edited_at: "invalid",
        },
      ],
    };
    await renderDetail(this);

    assert.dom('[data-field="opened"] dd').hasText("-");
    assert.dom('[data-field="closed"] dd').hasText("-");
    assert.dom(".atcp-case-detail__update-time").hasAttribute("title", "-");
    assert.dom(".atcp-case-detail__update-time").hasText("-");
  });

  test("renders the not found state with a back link", async function (assert) {
    this.error = "not_found";
    await renderDetail(this);

    assert.dom(".atcp-case-detail__not-found h1").hasText("Case not found");
    assert
      .dom(".atcp-case-detail__back")
      .hasText("← Case Management")
      .hasAttribute("href", "/internal/cases?severity=High");
    assert.dom(".atcp-case-detail__title").doesNotExist();
  });
});
