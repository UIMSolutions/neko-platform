sap.ui.define([
	"hdb/client/controller/BaseController"
], function (BaseController) {
	"use strict";

	/** Virtueller Assistent: Aufträge als Text, ausgeführt mit den Rechten der Anmeldung. */
	return BaseController.extend("hdb.client.controller.Assistant", {
		route: "assistant",

		onInit: function () {
			BaseController.prototype.onInit.apply(this, arguments);
			this.getView().getModel("view").setData({
				busy: false, draft: "", messages: [],
				suggestions: ["status", "summarize issues", "run advisors", "show expensive statements", "how do I restore a backup?"]
			});
		},

		onShow: function () {
			const app = this.getOwnerComponent().getModel("app");
			if (app.getProperty("/isSystem")) {
				this.getView().getModel("view").setProperty("/suggestions",
					["status of instances", "how do I create an instance?", "how do I scale?"]);
			}
		},

		onSuggestion: function (event) {
			this._ask(event.getSource().getText());
		},

		onSend: function () {
			this._ask(this.getView().getModel("view").getProperty("/draft"));
		},

		onClear: function () {
			this.getView().getModel("view").setProperty("/messages", []);
		},

		_ask: function (message) {
			const text = (message || "").trim();
			if (!text) {
				return;
			}
			const view = this.getView().getModel("view");
			const app = this.getOwnerComponent().getModel("app");
			const messages = view.getProperty("/messages").concat([{ sender: app.getProperty("/user"), icon: "sap-icon://person-placeholder", text: text }]);
			view.setProperty("/messages", messages);
			view.setProperty("/draft", "");
			view.setProperty("/busy", true);
			this.api("/api/v1/assistant", "POST", { message: text }).then(function (reply) {
				view.setProperty("/busy", false);
				view.setProperty("/messages", view.getProperty("/messages").concat([{ sender: this.text("assistant"), icon: "sap-icon://da-2", text: reply.text }]));
				if (reply.suggestions && reply.suggestions.length) {
					view.setProperty("/suggestions", reply.suggestions);
				}
			}.bind(this), function (error) {
				view.setProperty("/busy", false);
				this.fail(error);
			}.bind(this));
		}
	});
});
