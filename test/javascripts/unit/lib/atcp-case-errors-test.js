import { module, test } from "qunit";
import { normalizeCaseErrors } from "discourse/plugins/discourse-atcp-case/discourse/lib/atcp-case-errors";

module("Unit | Lib | atcp-case-errors", function () {
  test("normalizes field errors", function (assert) {
    assert.deepEqual(
      normalizeCaseErrors({
        errors: {
          title: ["Title is required"],
          product_ids: ["Products are required"],
        },
      }),
      {
        fieldErrors: {
          title: ["Title is required"],
          product_ids: ["Products are required"],
        },
        baseErrors: [],
      }
    );
  });

  test("normalizes base errors from a hash and an array", function (assert) {
    assert.deepEqual(
      normalizeCaseErrors({ errors: { base: ["Case is locked"] } }),
      { fieldErrors: {}, baseErrors: ["Case is locked"] }
    );

    assert.deepEqual(normalizeCaseErrors({ errors: ["Invalid request"] }), {
      fieldErrors: {},
      baseErrors: ["Invalid request"],
    });
  });

  test("normalizes mixed base and field errors", function (assert) {
    assert.deepEqual(
      normalizeCaseErrors({
        errors: {
          base: ["Unable to save"],
          source: ["Source is too long"],
        },
      }),
      {
        fieldErrors: { source: ["Source is too long"] },
        baseErrors: ["Unable to save"],
      }
    );
  });

  test("handles missing and unexpected values without throwing", function (assert) {
    assert.deepEqual(normalizeCaseErrors(), { fieldErrors: {}, baseErrors: [] });
    assert.deepEqual(normalizeCaseErrors({}), {
      fieldErrors: {},
      baseErrors: [],
    });
    assert.deepEqual(normalizeCaseErrors({ errors: null }), {
      fieldErrors: {},
      baseErrors: [],
    });
    assert.deepEqual(normalizeCaseErrors({ errors: { title: null } }), {
      fieldErrors: {},
      baseErrors: [],
    });
    assert.deepEqual(normalizeCaseErrors("unexpected"), {
      fieldErrors: {},
      baseErrors: [],
    });
  });

  test("coerces scalar messages and trims blanks", function (assert) {
    assert.deepEqual(
      normalizeCaseErrors({
        errors: [422, "  ", null, "Retry"],
      }),
      { fieldErrors: {}, baseErrors: ["422", "Retry"] }
    );
  });
});
