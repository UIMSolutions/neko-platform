sap.ui.define([], function () {
	"use strict";

	/** Der Mock-Stand aus localService muss die Entity Sets enthalten, an die die Cloud-Seiten binden. */
	QUnit.module("localService");

	QUnit.test("cloud metadata has the bound entity sets", function (assert) {
		const done = assert.async();
		fetch(sap.ui.require.toUrl("hdb/client/localService/metadata.xml")).then(function (r) {
			return r.text();
		}).then(function (xml) {
			["Traces", "Recommendations", "WorkloadClasses", "WorkloadMappings", "CalculationViews", "Bindings", "DataProducts"]
				.forEach(function (set) {
					assert.ok(xml.indexOf('EntitySet Name="' + set + '"') >= 0, set);
				});
			done();
		});
	});
});
