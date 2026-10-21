import { setupTest } from "ember-qunit";
import { module, test } from "qunit";

module("Unit | Route | atcp-cases index", function (hooks) {
  setupTest(hooks);

  test("keeps isLoading while overlapping refreshes are pending", async function (assert) {
    const route = this.owner.lookup("route:atcp-cases/index");
    const controller = { isLoading: false };
    const pending = [];

    route.controllerFor = () => controller;
    route._fetchList = () =>
      new Promise((resolve) => pending.push(resolve));
    route._fetchOnce = () => Promise.resolve({});

    const first = route.model({});
    const second = route.model({});

    assert.true(controller.isLoading, "loading starts with the first request");

    pending[0]({ data: { cases: [] }, error: null });
    await first;

    assert.true(
      controller.isLoading,
      "the first request finishing does not stop the second request's loading state"
    );

    pending[1]({ data: { cases: [] }, error: null });
    await second;

    assert.false(controller.isLoading, "loading stops after the last request");
  });
});
