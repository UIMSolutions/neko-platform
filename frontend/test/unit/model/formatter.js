/*global QUnit */
sap.ui.define([
  "neko/platform/model/formatter",
  "sap/ui/core/library"
], function (formatter, coreLibrary) {
  "use strict";

  var ValueState = coreLibrary.ValueState;

  QUnit.module("formatter");

  QUnit.test("service status → value state", function (assert) {
    assert.strictEqual(formatter.serviceStatusState("active"), ValueState.Success);
    assert.strictEqual(formatter.serviceStatusState("suspended"), ValueState.Warning);
    assert.strictEqual(formatter.serviceStatusState("retired"), ValueState.Error);
    assert.strictEqual(formatter.serviceStatusState("registered"), ValueState.Information);
  });

  QUnit.test("health → value state and icon", function (assert) {
    assert.strictEqual(formatter.healthState("up"), ValueState.Success);
    assert.strictEqual(formatter.healthState("down"), ValueState.Error);
    assert.strictEqual(formatter.healthState("unknown"), ValueState.None);
    assert.strictEqual(formatter.healthIcon("down"), "sap-icon://status-negative");
  });

  QUnit.test("domain classification gets stronger colours", function (assert) {
    assert.strictEqual(formatter.domainState("open"), ValueState.Success);
    assert.strictEqual(formatter.domainState("secret"), ValueState.Error);
  });

  QUnit.test("bytes", function (assert) {
    assert.strictEqual(formatter.bytes(512), "512 B");
    assert.strictEqual(formatter.bytes(1536), "1.5 KB");
    assert.strictEqual(formatter.bytes(734003), "716.8 KB");
    assert.strictEqual(formatter.bytes(null), "");
  });

  QUnit.test("enum texts fall back to the raw value without a component", function (assert) {
    assert.strictEqual(formatter.serviceStatusText.call(null, "active"), "active");
    assert.strictEqual(formatter.serviceStatusText.call(null, ""), "");
  });

  QUnit.test("checksum and direction helpers", function (assert) {
    assert.strictEqual(formatter.checksumShort("0123456789abcdef"), "0123456789ab…");
    assert.ok(formatter.isOutbound("outbound"));
    assert.notOk(formatter.isOutbound("inbound"));
  });
});
