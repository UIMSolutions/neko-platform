sap.ui.define([
  "uim/identitydirectory/model/service"
], function (Service) {
  "use strict";

  QUnit.module("service");

  QUnit.test("keyPath escapes quotes", function (assert) {
    assert.strictEqual(Service.keyPath("Users", "a'b"), "Users('a''b')");
  });
});
