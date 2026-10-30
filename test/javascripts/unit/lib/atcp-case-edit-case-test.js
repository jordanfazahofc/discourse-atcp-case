import { setupTest } from "ember-qunit";
import { module, test } from "qunit";
import {
  buildEditCasePayload,
  editCaseInitialData,
  editCaseProductItems,
  orphanCaseProducts,
} from "discourse/plugins/discourse-atcp-case/discourse/lib/atcp-case-edit-case";
import { openCase } from "../../fixtures/atcp-case-detail";

module("Unit | Lib | atcp-case-edit-case", function (hooks) {
  setupTest(hooks);

  test("builds initial data from linked products only", function (assert) {
    const atcpCase = openCase({
      assignee: { id: 5, username: "jordan", name: "Jordan" },
    });

    assert.deepEqual(editCaseInitialData(atcpCase), {
      title: "Fan noise on boot",
      case_type: "Hardware",
      severity: "Critical",
      source: "Branch technician",
      product_ids: ["11", "12"],
      assignee_id: "5",
    });

    assert.deepEqual(
      editCaseProductItems(atcpCase).map((product) => product.id),
      ["11", "12"]
    );
    assert.deepEqual(
      orphanCaseProducts(atcpCase).map((product) => product.name),
      ["Legacy Axioo"]
    );
  });

  test("sends only changed fields", function (assert) {
    const atcpCase = openCase();
    const initial = editCaseInitialData(atcpCase);

    assert.deepEqual(
      buildEditCasePayload({ atcpCase, data: initial }),
      {},
      "unchanged data produces an empty payload"
    );

    assert.deepEqual(
      buildEditCasePayload({
        atcpCase,
        data: {
          ...initial,
          title: " Updated title ",
          severity: "High",
          product_ids: ["12", "11"],
        },
        productsTouched: true,
      }),
      { title: "Updated title", severity: "High" },
      "ignores trimmed and reordered values that did not change"
    );

    assert.deepEqual(
      buildEditCasePayload({
        atcpCase,
        data: { ...initial, product_ids: ["12"] },
        productsTouched: true,
      }),
      { product_ids: ["12"] }
    );
  });

  test("sends a cleared assignee only when it changed", function (assert) {
    const atcpCase = openCase({
      assignee: { id: 5, username: "jordan", name: "Jordan" },
    });
    const initial = editCaseInitialData(atcpCase);

    assert.deepEqual(
      buildEditCasePayload({ atcpCase, data: { ...initial, assignee_id: "" } }),
      { assignee_id: "" }
    );
    assert.deepEqual(
      buildEditCasePayload({
        atcpCase,
        data: { ...initial, assignee_id: "9" },
      }),
      { assignee_id: "9" }
    );
  });
});
