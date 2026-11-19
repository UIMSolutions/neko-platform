sap.ui.define([
	"hdb/client/controller/BaseController"
], function (BaseController) {
	"use strict";

	/** Index-, NSE-, Partition-, Performance-Class- und ECN-Advisor des Mandanten. */
	return BaseController.extend("hdb.client.controller.Advisors", {
		route: "advisors",

		onRun: function () {
			this.run(this.api("/api/v1/advisors/run", "POST", {}), "advisorsDone");
		}
	});
});
