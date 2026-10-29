import { click, render, settled, waitFor } from "@ember/test-helpers";
import moment from "moment";
import { module, test } from "qunit";
import { setupRenderingTest } from "discourse/tests/helpers/component-test";
import AtcpCaseDetail from "discourse/plugins/discourse-atcp-case/discourse/components/atcp-case/detail";
import {
  DETAIL_CASE,
  emptyCase,
  initialReportCase,
  openCase,
} from "../../fixtures/atcp-case-detail";

module("Integration | Component | AtcpCaseDetail", function (hooks) {
  setupRenderingTest(hooks);

  hooks.afterEach(async function () {
    const openLightbox = document.querySelector(".pswp--open");

    if (openLightbox) {
      openLightbox.dispatchEvent(
        new KeyboardEvent("keydown", { key: "Escape", bubbles: true })
      );
      await settled();
    }

    document.querySelectorAll(".pswp").forEach((element) => element.remove());
  });

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
      .dom('[data-field="product"] li')
      .exists({ count: 3 }, "each product is its own list item");
    assert.deepEqual(
      Array.from(
        document.querySelectorAll('[data-field="product"] li')
      ).map((item) => item.textContent.trim()),
      ["Axioo P15 (AXIOO-P15)", "Legacy Axioo", "PRO L7 (NBAX22X)"],
      "product labels append the SKU only once"
    );
    assert
      .dom('[data-field="opened"] dd')
      .hasText(moment(DETAIL_CASE.opened_at).format("D MMM YYYY"));
    assert.dom('[data-field="aging"] dd').hasText("5 days");
    assert.dom('[data-field="source"] dd').hasText("Branch technician");
    assert.dom('[data-field="reporter"] dd').hasText("Jordan");
    assert
      .dom('[data-field="closed"] dd')
      .hasText(moment(DETAIL_CASE.closed_at).format("D MMM YYYY"));
    assert.dom('[data-field="close_reason"] dd').hasText("Resolved");
    assert
      .dom(".atcp-case-detail__summary")
      .doesNotIncludeText("Affected units");
  });

  test("renders a single product as one list item", async function (assert) {
    this.atcpCase = {
      ...openCase(),
      products: [{ id: 11, name: "Axioo P15", sku: "AXIOO-P15" }],
    };
    await renderDetail(this);

    assert.dom('[data-field="product"] ul').exists();
    assert.dom('[data-field="product"] li').exists({ count: 1 });
    assert
      .dom('[data-field="product"] li')
      .hasText("Axioo P15 (AXIOO-P15)");
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

  test("renders initial report attachments below the summary", async function (assert) {
    this.atcpCase = initialReportCase();
    await renderDetail(this);

    assert
      .dom(".atcp-case-detail__initial-report-title")
      .hasText("Initial report (2)");
    assert
      .dom(".atcp-case-detail__initial-report .atcp-case-attachment-gallery__item")
      .exists({ count: 2 });
    assert
      .dom(".atcp-case-detail__initial-report .atcp-case-attachment-gallery__image")
      .hasAttribute("src", "/uploads/default/original/1X/initial-photo.png")
      .hasAttribute("alt", "initial-photo.png");
    assert
      .dom(".atcp-case-detail__initial-report")
      .includesText("initial-report.pdf 96 KB");
  });

  test("hides the initial report when only normal updates have attachments", async function (assert) {
    this.atcpCase = openCase();
    await renderDetail(this);

    assert.dom(".atcp-case-detail__initial-report").doesNotExist();
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

  test("shows the technical edit action for a manageable open case", async function (assert) {
    this.activeTab = "technical";
    this.atcpCase = openCase({ can_manage: true });
    await renderDetail(this);

    assert.dom(".atcp-case-detail__technical-title").hasText("Technical");
    assert
      .dom(".atcp-case-detail__technical-edit")
      .hasText("Edit")
      .hasAttribute("id", "atcp-case-technical-edit");
  });

  test("hides the technical edit action for a closed case", async function (assert) {
    this.activeTab = "technical";
    this.atcpCase = DETAIL_CASE;
    await renderDetail(this);

    assert.dom(".atcp-case-detail__technical-edit").doesNotExist();
  });

  test("hides the technical edit action when the case is not manageable", async function (assert) {
    this.activeTab = "technical";
    this.atcpCase = openCase({ can_manage: false });
    await renderDetail(this);

    assert.dom(".atcp-case-detail__technical-edit").doesNotExist();
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

  test("opens the initial report image in the lightbox", async function (assert) {
    this.atcpCase = initialReportCase();
    await renderDetail(this);

    const originalOpen = window.open;
    let openedWindows = 0;
    window.open = () => {
      openedWindows += 1;
      return null;
    };

    try {
      await click(".atcp-case-detail__initial-report .lightbox");
      await waitFor(".pswp--open");
    } finally {
      window.open = originalOpen;
    }

    assert.dom(".pswp").exists("opens the image popup");
    assert.strictEqual(openedWindows, 0, "does not open a new window");
    assert
      .dom(".pswp__caption-title")
      .hasText("initial-photo.png", "uses the attachment filename");
  });

  test("exposes lightbox data on images and keeps documents plain", async function (assert) {
    this.atcpCase = initialReportCase();
    await renderDetail(this);

    const summaryImage = document.querySelector(
      ".atcp-case-detail__initial-report a.lightbox"
    );
    const summaryDocument = [
      ...document.querySelectorAll(".atcp-case-detail__initial-report a"),
    ].find((anchor) => anchor.textContent.includes("initial-report.pdf"));

    assert
      .dom(summaryImage)
      .hasAttribute("href", "/uploads/default/original/1X/initial-photo.png")
      .hasAttribute(
        "data-large-src",
        "/uploads/default/original/1X/initial-photo.png"
      )
      .hasAttribute(
        "data-orig-src",
        "/uploads/default/original/1X/initial-photo.png"
      )
      .hasAttribute(
        "data-download-href",
        "/uploads/default/original/1X/initial-photo.png"
      );
    assert.dom(summaryDocument).doesNotHaveClass("lightbox");

    const progressImage = document.querySelector(
      ".atcp-case-detail__update a.atcp-case-detail__attachment.lightbox"
    );
    assert
      .dom(progressImage)
      .hasAttribute("data-large-src", "/uploads/default/original/1X/photo.png")
      .hasAttribute("data-orig-src", "/uploads/default/original/1X/photo.png")
      .hasAttribute(
        "data-download-href",
        "/uploads/default/original/1X/photo.png"
      );

    this.activeTab = "attachments";
    await renderDetail(this);

    const tabImage = document.querySelector(
      ".atcp-case-detail__attachment-preview.lightbox"
    );
    assert
      .dom(tabImage)
      .hasAttribute("data-large-src", "/uploads/default/original/1X/photo.png")
      .hasAttribute("data-orig-src", "/uploads/default/original/1X/photo.png")
      .hasAttribute(
        "data-download-href",
        "/uploads/default/original/1X/photo.png"
      );
  });

  test("opens an update image in the lightbox", async function (assert) {
    await renderDetail(this);

    await click(
      ".atcp-case-detail__update .atcp-case-detail__attachment.lightbox"
    );
    await waitFor(".pswp--open");

    assert.dom(".pswp").exists("opens the image popup from the progress log");
  });

  test("opens an attachment tab image in the lightbox", async function (assert) {
    this.activeTab = "attachments";
    await renderDetail(this);

    await click(".atcp-case-detail__attachment-preview.lightbox");
    await waitFor(".pswp--open");

    assert.dom(".pswp").exists("opens the image popup from the attachments tab");
    assert.dom(".pswp__caption-title").hasText("fan-noise.png");
  });

  test("keeps document links out of the lightbox", async function (assert) {
    this.activeTab = "attachments";
    await renderDetail(this);

    const previews = document.querySelectorAll(
      ".atcp-case-detail__attachment-preview"
    );

    assert.dom(previews[0]).hasClass("lightbox");
    assert.dom(previews[1]).doesNotHaveClass("lightbox");
    assert.dom(".atcp-case-detail__attachment-link.lightbox").doesNotExist();
  });

  test("refreshes the lightbox after initial report attachments change", async function (assert) {
    const initial = initialReportCase();
    this.atcpCase = initial;
    await renderDetail(this);

    const initialKey = document.querySelector(
      ".atcp-case-detail__initial-report .atcp-case-attachment-gallery"
    ).dataset.galleryKey;

    this.atcpCase = {
      ...initial,
      updates: initial.updates.map((update) =>
        update.initial_report
          ? {
              ...update,
              attachments: [
                {
                  id: 205,
                  upload_id: 107,
                  url: "/uploads/default/original/1X/updated-photo.png",
                  original_filename: "updated-photo.png",
                  human_filesize: "64 KB",
                  is_image: true,
                },
              ],
            }
          : update
      ),
    };
    await renderDetail(this);

    const refreshedGallery = document.querySelector(
      ".atcp-case-detail__initial-report .atcp-case-attachment-gallery"
    );
    assert.notStrictEqual(
      refreshedGallery.dataset.galleryKey,
      initialKey,
      "recreates the gallery when the attachment list changes"
    );

    await click(".atcp-case-detail__initial-report .lightbox");
    await waitFor(".pswp--open");

    assert.dom(".pswp__caption-title").hasText("updated-photo.png");
  });

  test("renders empty case states", async function (assert) {
    this.atcpCase = emptyCase();
    await renderDetail(this);

    assert
      .dom('[data-field="product"] dd')
      .hasText("No product linked");
    assert.dom('[data-field="product"] ul').doesNotExist();
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
