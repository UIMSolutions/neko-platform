sap.ui.define([
	"hdb/client/controller/BaseController",
	"sap/m/Button",
	"sap/m/Dialog",
	"sap/m/Input",
	"sap/m/Label",
	"sap/m/MessageStrip",
	"sap/m/TextArea",
	"sap/ui/layout/form/SimpleForm"
], function (BaseController, Button, Dialog, Input, Label, MessageStrip, TextArea, SimpleForm) {
	"use strict";

	/** Anwendungen binden: technischer Benutzer und Zugangsdaten im Format von VCAP_SERVICES. */
	return BaseController.extend("hdb.client.controller.Bindings", {
		route: "bindings",

		onCreate: function () {
			const name = new Input({ required: true });
			const application = new Input({ required: true });
			const role = new Input({ value: "editor" });
			const dialog = new Dialog({
				title: this.text("bindApplication"),
				contentWidth: "28rem",
				content: [new SimpleForm({ editable: true, layout: "ColumnLayout", content: [
					new Label({ text: this.text("binding"), required: true }), name,
					new Label({ text: this.text("application"), required: true }), application,
					new Label({ text: this.text("role") }), role
				] })],
				beginButton: new Button({ text: this.text("bind"), type: "Emphasized", press: function () {
					this.run(this.api("/api/v1/bindings", "POST", {
						name: name.getValue().trim(), application: application.getValue(), role: role.getValue()
					})).then(function (result) {
						dialog.close();
						this._showCredentials(result.credentials);
					}.bind(this), function () { /* Meldung zeigt run() */ });
				}.bind(this) }),
				endButton: new Button({ text: this.text("cancel"), press: function () {
					dialog.close();
				} }),
				afterClose: function () {
					dialog.destroy();
				}
			});
			this.getView().addDependent(dialog);
			dialog.open();
		},

		_showCredentials: function (credentials) {
			const dialog = new Dialog({
				title: this.text("credentials"),
				contentWidth: "36rem",
				content: [
					new MessageStrip({ text: this.text("credentialsOnce"), type: "Warning", showIcon: true }).addStyleClass("sapUiSmallMargin"),
					new TextArea({ value: JSON.stringify(credentials, null, 2), rows: 18, width: "100%", editable: false }).addStyleClass("sapUiSmallMarginBeginEnd")
				],
				endButton: new Button({ text: this.text("close"), press: function () {
					dialog.close();
				} }),
				afterClose: function () {
					dialog.destroy();
				}
			});
			this.getView().addDependent(dialog);
			dialog.open();
		},

		onDelete: function (event) {
			const row = this.rowOf(event);
			this.confirm("unbindConfirm", [row.name]).then(function () {
				this.run(this.api("/api/v1/bindings/" + encodeURIComponent(row.name), "DELETE"), "unbound", [row.name]);
			}.bind(this));
		}
	});
});
