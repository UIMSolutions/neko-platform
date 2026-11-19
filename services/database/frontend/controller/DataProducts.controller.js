sap.ui.define([
	"hdb/client/controller/BaseController"
], function (BaseController) {
	"use strict";

	/** Freigegebene Datenprodukte installieren und entfernen; danach kennt das Tabellen-Set die neuen Tabellen. */
	return BaseController.extend("hdb.client.controller.DataProducts", {
		route: "dataproducts",

		_reloadSets: function () {
			return this.getOwnerComponent().loadEntitySets().catch(function () { /* Liste bleibt */ });
		},

		onInstall: function (event) {
			const row = this.rowOf(event);
			this.run(this.api("/api/v1/dataproducts/" + encodeURIComponent(row.id) + "/install", "POST"), "productInstalled", [row.title])
				.then(this._reloadSets.bind(this));
		},

		onUninstall: function (event) {
			const row = this.rowOf(event);
			this.confirm("uninstallConfirm", [row.title]).then(function () {
				this.run(this.api("/api/v1/dataproducts/" + encodeURIComponent(row.id) + "/install", "DELETE"), "productUninstalled", [row.title])
					.then(this._reloadSets.bind(this));
			}.bind(this));
		}
	});
});
