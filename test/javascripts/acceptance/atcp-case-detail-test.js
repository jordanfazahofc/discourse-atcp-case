import { click, currentURL, fillIn, settled, visit } from "@ember/test-helpers";
import { test } from "qunit";
import { parsePostData } from "discourse/tests/helpers/create-pretender";
import { acceptance, createFile } from "discourse/tests/helpers/qunit-helpers";
import { openCase } from "../fixtures/atcp-case-detail";

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
let addedUpdates = [];
let editedUpdates = {};
let submittedPayload = null;
let editedPayload = null;
let caseTwoPayload = null;
let technicalPayload = null;
let caseEditPayload = null;
let technicalFailureStatus = null;

const UPLOAD_RESPONSE = {
  id: 501,
  url: "/uploads/default/original/1X/diagnostic.pdf",
  short_url: "upload://diagnostic.pdf",
  original_filename: "diagnostic.pdf",
  human_filesize: "12 KB",
  filesize: 12_000,
  extension: "pdf",
};

function caseFor(id) {
  const atcpCase = openCase({
    id: Number(id),
    case_number: `CASE-2026-${String(id).padStart(4, "0")}`,
    title: id === "2" ? "Keyboard backlight flicker" : "Fan noise on boot",
  });

  if (id === "1" && technicalPayload) {
    Object.assign(atcpCase, technicalPayload);
  }

  if (id === "1" && caseEditPayload) {
    Object.assign(atcpCase, caseEditPayload);
  }

  atcpCase.updates = [...addedUpdates, ...atcpCase.updates].map((update) =>
    editedUpdates[update.id]
      ? { ...update, ...editedUpdates[update.id] }
      : update
  );
  return atcpCase;
}

acceptance("ATCP | Case detail", function (needs) {
  needs.user({ atcp_internal_access: true });
  needs.settings({ atcp_case_enabled: true });

  needs.hooks.beforeEach(function () {
    detailRequests = [];
    missingCaseId = null;
    addedUpdates = [];
    editedUpdates = {};
    submittedPayload = null;
    editedPayload = null;
    caseTwoPayload = null;
    technicalPayload = null;
    caseEditPayload = null;
    technicalFailureStatus = null;
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
        statuses: ["Open", "In Progress", "On Hold", "Solution Found", "Closed"],
        close_reasons: ["Resolved"],
        frequencies: ["Intermittent", "Always", "Specific conditions"],
        reproducibilities: [
          "Reproducible",
          "Not reproducible",
          "Not tried",
        ],
        upload: { extensions: ["pdf", "png"], max_mb: 2 },
      })
    );

    server.get("/atcp/cases/pic_candidates.json", () =>
      helper.response({ groups: [] })
    );

    server.post("/uploads.json", () => helper.response(UPLOAD_RESPONSE));

    server.post("/atcp/cases/1/updates.json", (request) => {
      submittedPayload = parsePostData(request.requestBody);
      const update = {
        id: 900,
        can_edit: true,
        can_delete: true,
        update_type: submittedPayload.update_type,
        body: submittedPayload.body,
        is_system: false,
        system_event: null,
        from_value: null,
        to_value: null,
        details: {},
        edited_at: null,
        created_at: "2026-07-16T04:00:00.000Z",
        user: { id: 1, username: "system", name: "System" },
        attachments: [],
      };
      addedUpdates.unshift(update);
      return helper.response({ update });
    });

    server.post("/atcp/cases/2/updates.json", (request) => {
      caseTwoPayload = parsePostData(request.requestBody);
      return helper.response({ status: "Open" });
    });

    server.put("/atcp/cases/1/updates/29.json", (request) => {
      editedPayload = parsePostData(request.requestBody);
      const update = openCase().updates.find((item) => item.id === 29);
      editedUpdates[29] = {
        ...update,
        ...editedPayload,
        edited_at: "2026-07-16T05:00:00.000Z",
      };
      return helper.response({ update: editedUpdates[29] });
    });

    server.put("/atcp/cases/1.json", (request) => {
      const payload = parsePostData(request.requestBody);

      if (technicalFailureStatus) {
        return helper.response(technicalFailureStatus, {
          errors: ["Case is closed"],
        });
      }

      if (Object.hasOwn(payload, "title")) {
        caseEditPayload = payload;
      } else {
        technicalPayload = payload;
      }

      return helper.response({ case: caseFor("1") });
    });

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

  test("adds an update and keeps the progress tab", async function (assert) {
    await visit("/internal/cases/1");

    await click(".atcp-case-detail-add-update__toggle");
    await fillIn(
      ".atcp-case-detail-add-update .form-kit__field[data-name='body'] textarea",
      "Replaced the fan curve."
    );
    await click(".atcp-case-detail-add-update__submit");

    assert.deepEqual(submittedPayload, {
      update_type: "Update case",
      body: "Replaced the fan curve.",
    });
    assert.strictEqual(currentURL(), "/internal/cases/1", "stays on progress");
    assert.strictEqual(detailRequests.length, 2, "refreshes the case");
    assert
      .dom(".atcp-case-detail__progress")
      .includesText("Replaced the fan curve.");
    assert
      .dom(".atcp-case-detail__tab[data-tab='progress']")
      .hasAttribute("aria-selected", "true");
  });

  test("edits an update inline and refreshes the timeline", async function (assert) {
    await visit("/internal/cases/1");

    await click("#atcp-case-update-edit-29");

    assert.dom(".atcp-case-detail-edit-update").exists();
    assert
      .dom(
        ".atcp-case-detail-edit-update .form-kit__field[data-name='update_type'] input"
      )
      .hasValue("Vendor communication");

    await fillIn(
      ".atcp-case-detail-edit-update .form-kit__field[data-name='update_type'] input",
      "Internal note"
    );
    await fillIn(
      ".atcp-case-detail-edit-update .form-kit__field[data-name='body'] textarea",
      "  Edited the timeline entry.  "
    );
    await click(".atcp-case-detail-edit-update__save");

    assert.deepEqual(editedPayload, {
      update_type: "Internal note",
      body: "Edited the timeline entry.",
    });
    assert.strictEqual(detailRequests.length, 2, "refreshes the case");
    assert.dom(".atcp-case-detail-edit-update").doesNotExist();
    assert
      .dom(".atcp-case-detail__update-type")
      .hasText("Internal note");
    assert
      .dom(".atcp-case-detail__update-body")
      .includesText("Edited the timeline entry.");
    assert.strictEqual(currentURL(), "/internal/cases/1", "stays on progress");
  });

  test("aligns updates and history with the author column", async function (assert) {
    await visit("/internal/cases/1");

    assert
      .dom(".atcp-case-detail__history-summary")
      .hasText("Previous versions (2)");

    const left = (selector) =>
      document.querySelector(selector)?.getBoundingClientRect().left;
    const authorLeft = left(".atcp-case-detail__update-author");

    assert.true(
      Math.abs(left(".atcp-case-detail__update-body") - authorLeft) < 0.5,
      "the note starts in the author column"
    );
    assert.true(
      Math.abs(left(".atcp-case-detail__update-attachments") - authorLeft) <
        0.5,
      "attachments start in the author column"
    );
    assert.true(
      Math.abs(left(".atcp-case-detail__history") - authorLeft) < 0.5,
      "history starts in the author column"
    );
    assert.true(
      Math.abs(
        left(".atcp-case-detail__system-update-content") - authorLeft
      ) < 0.5,
      "system entries start in the author column"
    );

    await click("#atcp-case-update-edit-29");

    assert.true(
      Math.abs(left(".atcp-case-detail-edit-update") - authorLeft) < 0.5,
      "the editor starts in the author column"
    );
  });

  test("resets the add update form when switching cases", async function (assert) {
    await visit("/internal/cases/1");

    await click(".atcp-case-detail-add-update__toggle");
    await fillIn(
      ".atcp-case-detail-add-update .form-kit__field[data-name='body'] textarea",
      "Case one draft."
    );
    await fillIn(
      ".atcp-case-detail-add-update .form-kit__field[data-name='update_type'] input",
      "Vendor communication"
    );
    assert
      .dom(".atcp-case-detail-add-update .form-kit__field[data-name='update_type'] input")
      .hasValue("Vendor communication");

    const appEvents = this.owner.lookup("service:app-events");
    const uploaded = new Promise((resolve) => {
      appEvents.one(
        "upload-mixin:atcp-case-add-update-1:all-uploads-complete",
        resolve
      );
    });
    appEvents.trigger(
      "upload-mixin:atcp-case-add-update-1:add-files",
      createFile("diagnostic.pdf", "application/pdf")
    );
    await uploaded;
    await settled();

    assert.dom(".atcp-case-detail-add-update__file").exists({ count: 1 });

    try {
      await this.owner
        .lookup("service:router")
        .transitionTo("atcp-cases.show", "2");
    } catch (error) {
      assert.strictEqual(error.name, "TransitionAborted");
    }
    await settled();

    assert
      .dom(".dialog-footer .btn-primary")
      .exists("confirms before discarding the draft");
    await click(".dialog-footer .btn-primary");

    assert.dom(".atcp-case-detail-add-update form").doesNotExist();
    assert.dom(".atcp-case-detail-add-update__toggle").exists();

    await click(".atcp-case-detail-add-update__toggle");

    assert
      .dom(".atcp-case-detail-add-update .form-kit__field[data-name='body'] textarea")
      .hasValue("", "the draft note is not carried over");
    assert
      .dom(".atcp-case-detail-add-update__file")
      .doesNotExist("the selected file is not carried over");
    assert
      .dom(".atcp-case-detail-add-update .form-kit__field[data-name='update_type'] input")
      .hasValue("", "the update type is reset");

    await fillIn(
      ".atcp-case-detail-add-update .form-kit__field[data-name='body'] textarea",
      "Case two note."
    );
    await click(".atcp-case-detail-add-update__submit");

    assert.deepEqual(caseTwoPayload, {
      update_type: "Update case",
      body: "Case two note.",
    });
  });

  test("edits technical details and keeps the technical tab", async function (assert) {
    await visit("/internal/cases/1?tab=technical");

    assert.dom(".atcp-case-detail__technical-edit").exists();

    await click(".atcp-case-detail__technical-edit");
    assert.dom(".atcp-case-edit-technical-modal").exists();

    await fillIn(
      ".atcp-case-edit-technical-modal .form-kit__field[data-name='symptom'] textarea",
      "  Updated fan noise.  "
    );
    await click(".atcp-case-edit-technical-modal__save");

    assert.deepEqual(technicalPayload, { symptom: "Updated fan noise." });
    assert.strictEqual(currentURL(), "/internal/cases/1?tab=technical");
    assert.strictEqual(detailRequests.length, 2, "refreshes the case");
    assert.dom(".atcp-case-edit-technical-modal").doesNotExist();
    assert
      .dom('[data-field="symptom"] dd')
      .includesText("Updated fan noise.");
    assert.strictEqual(
      document.activeElement,
      document.querySelector(".atcp-case-detail__technical-edit"),
      "focus returns to the Edit button"
    );
  });

  test("edits the case header and keeps the current tab", async function (assert) {
    await visit("/internal/cases/1?tab=technical");

    assert.dom(".atcp-case-detail__edit").hasText("Edit case");

    await click(".atcp-case-detail__edit");
    assert.dom(".atcp-case-edit-case-modal").exists();
    assert
      .dom(".atcp-case-edit-case-modal__orphan-products")
      .includesText("Legacy Axioo");

    await fillIn(
      ".atcp-case-edit-case-modal .form-kit__field[data-name='title'] input",
      "  Updated case title  "
    );
    await click(".atcp-case-edit-case-modal__submit");

    assert.deepEqual(caseEditPayload, { title: "Updated case title" });
    assert.strictEqual(currentURL(), "/internal/cases/1?tab=technical");
    assert.strictEqual(detailRequests.length, 2, "refreshes the case");
    assert.dom(".atcp-case-edit-case-modal").doesNotExist();
    assert
      .dom(".atcp-case-detail__title")
      .includesText("Updated case title");
    assert.strictEqual(
      document.activeElement,
      document.querySelector(".atcp-case-detail__edit"),
      "focus returns to the Edit case button"
    );
  });

  test("closes the technical editor when the case is no longer editable", async function (assert) {
    technicalFailureStatus = 403;

    await visit("/internal/cases/1?tab=technical");
    await click(".atcp-case-detail__technical-edit");
    await fillIn(
      ".atcp-case-edit-technical-modal .form-kit__field[data-name='symptom'] textarea",
      "Updated fan noise."
    );
    await click(".atcp-case-edit-technical-modal__save");

    assert.dom(".atcp-case-edit-technical-modal").doesNotExist();
    assert.strictEqual(currentURL(), "/internal/cases/1?tab=technical");
    assert.strictEqual(detailRequests.length, 2, "refreshes the case");
    assert.strictEqual(
      document.activeElement,
      document.querySelector(".atcp-case-detail__technical-edit"),
      "focus returns to the Edit button"
    );
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
