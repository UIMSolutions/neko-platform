sap.ui.define(["hdb/client/model/formatter"], function (formatter) {
	"use strict";

	QUnit.module("formatter");

	QUnit.test("severity and status states", function (assert) {
		assert.strictEqual(formatter.severityState("high"), "Error");
		assert.strictEqual(formatter.severityState("medium"), "Warning");
		assert.strictEqual(formatter.severityState("info"), "None");
		assert.strictEqual(formatter.statusState("running"), "Success");
		assert.strictEqual(formatter.statusState("stopped"), "Warning");
		assert.strictEqual(formatter.traceState("violation"), "Warning");
	});

	QUnit.test("sizes and durations", function (assert) {
		assert.strictEqual(formatter.bytes(512), "512 B");
		assert.strictEqual(formatter.bytes(1536), "1.5 KiB");
		assert.strictEqual(formatter.bytes(3 * 1024 * 1024 * 1024), "3.0 GiB");
		assert.strictEqual(formatter.ms(2.5), "2.50 ms");
		assert.strictEqual(formatter.ms(1500), "1.50 s");
		assert.strictEqual(formatter.percent(12.345), "12.3 %");
		assert.strictEqual(formatter.sizing(64, 8, 256), "64 GB · 8 vCPU · 256 GB");
	});
});
