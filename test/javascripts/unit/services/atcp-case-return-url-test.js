import { getOwner } from "@ember/owner";
import { setupTest } from "ember-qunit";
import { module, test } from "qunit";
import { CASE_LIST_URL } from "discourse/plugins/discourse-atcp-case/discourse/services/atcp-case-return-url";

module("Unit | Service | atcp-case-return-url", function (hooks) {
  setupTest(hooks);

  hooks.beforeEach(function () {
    this.service = getOwner(this).lookup("service:atcp-case-return-url");
  });

  test("starts at the case list", function (assert) {
    assert.strictEqual(this.service.url, CASE_LIST_URL);
  });

  test("accepts an internal filtered list URL", function (assert) {
    this.service.remember("/internal/cases?severity=High&page=2");

    assert.strictEqual(
      this.service.url,
      "/internal/cases?severity=High&page=2"
    );
  });

  test("ignores external, protocol-relative, and doubly-slashed URLs", function (assert) {
    this.service.remember("/internal/cases?severity=High");

    this.service.remember("https://example.com/internal/cases?severity=High");
    assert.strictEqual(
      this.service.url,
      "/internal/cases?severity=High",
      "an external URL is ignored"
    );

    this.service.remember("//example.com/internal/cases?severity=High");
    assert.strictEqual(
      this.service.url,
      "/internal/cases?severity=High",
      "a protocol-relative URL is ignored"
    );

    this.service.remember("/internal/cases?next=//example.com");
    assert.strictEqual(
      this.service.url,
      "/internal/cases?severity=High",
      "a value containing a double slash is ignored"
    );

    this.service.url = "http://example.com/internal/cases";
    assert.strictEqual(
      this.service.url,
      "/internal/cases?severity=High",
      "an unsafe direct assignment is ignored"
    );
  });

  test("ignores non-string values", function (assert) {
    this.service.remember("/internal/cases?page=2");
    const expected = this.service.url;

    for (const value of [null, undefined, 42, { url: "/internal/cases" }]) {
      this.service.remember(value);
      assert.strictEqual(this.service.url, expected);
    }
  });
});
