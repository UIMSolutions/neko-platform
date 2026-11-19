sap.ui.define([
	"hdb/client/controller/BaseController",
	"sap/m/Button",
	"sap/m/CheckBox",
	"sap/m/Dialog",
	"sap/m/Input",
	"sap/m/Label",
	"sap/m/MessageBox",
	"sap/m/Select",
	"sap/m/StepInput",
	"sap/ui/core/Item",
	"sap/ui/layout/form/SimpleForm"
], function (BaseController, Button, CheckBox, Dialog, Input, Label, MessageBox, Select, StepInput, Item, SimpleForm) {
	"use strict";

	const CLASSES = ["memory", "compute", "highMemory"];

	/** Instanzen (nur Systemadministratoren): anlegen, skalieren, starten, stoppen, löschen. */
	return BaseController.extend("hdb.client.controller.Instances", {
		route: "instances",

		_classSelect: function (selected) {
			return new Select({
				selectedKey: selected || "memory",
				items: CLASSES.map(function (key) {
					return new Item({ key: key, text: this.text("class_" + key) });
				}, this)
			});
		},

		_dialog: function (title, content, okText, onOk) {
			const dialog = new Dialog({
				title: title,
				contentWidth: "30rem",
				content: [new SimpleForm({ editable: true, layout: "ColumnLayout", content: content })],
				beginButton: new Button({ text: okText, type: "Emphasized", press: function () {
					onOk().then(function () {
						dialog.close();
					}, function () { /* Meldung zeigt run() */ });
				} }),
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

		onCreate: function () {
			const name = new Input({ required: true });
			const description = new Input();
			const memory = new StepInput({ value: 32, min: 16, max: 6144, step: 16 });
			const storage = new StepInput({ value: 0, min: 0, max: 32768, step: 16, description: this.text("storageAuto") });
			const performanceClass = this._classSelect();
			const nse = new CheckBox({ text: this.text("nseEnabled") });
			const ecn = new StepInput({ value: 0, min: 0, max: 4 });
			const admin = new Input({ value: "admin" });
			const password = new Input({ type: "Password" });
			this._dialog(this.text("createInstance"), [
				new Label({ text: this.text("instance"), required: true }), name,
				new Label({ text: this.text("description") }), description,
				new Label({ text: this.text("memoryGb") }), memory,
				new Label({ text: this.text("storageGb") }), storage,
				new Label({ text: this.text("performanceClass") }), performanceClass,
				new Label({ text: "" }), nse,
				new Label({ text: this.text("ecnNodes") }), ecn,
				new Label({ text: this.text("adminUser") }), admin,
				new Label({ text: this.text("adminPassword"), required: true }), password
			], this.text("create"), function () {
				const body = {
					name: name.getValue().trim(), description: description.getValue(), memoryGb: memory.getValue(),
					performanceClass: performanceClass.getSelectedKey(), nseEnabled: nse.getSelected(),
					ecnNodes: ecn.getValue(), adminName: admin.getValue(), adminPassword: password.getValue()
				};
				if (storage.getValue() > 0) {
					body.storageGb = storage.getValue();
				}
				return this.run(this.api("/api/v1/cloud/instances", "POST", body), "instanceCreated", [body.name]);
			}.bind(this));
		},

		onResize: function (event) {
			const row = this.rowOf(event);
			const memory = new StepInput({ value: row.memoryGb, min: 16, max: 6144, step: 16 });
			const storage = new StepInput({ value: row.storageGb, min: 32, max: 32768, step: 16 });
			const performanceClass = this._classSelect(row.performanceClass);
			const nse = new CheckBox({ text: this.text("nseEnabled"), selected: row.nseEnabled });
			const ecn = new StepInput({ value: row.ecnNodes, min: 0, max: 4 });
			this._dialog(this.text("resizeInstance", [row.name]), [
				new Label({ text: this.text("memoryGb") }), memory,
				new Label({ text: this.text("storageGb") }), storage,
				new Label({ text: this.text("performanceClass") }), performanceClass,
				new Label({ text: "" }), nse,
				new Label({ text: this.text("ecnNodes") }), ecn
			], this.text("apply"), function () {
				return this.run(this.api("/api/v1/cloud/instances/" + encodeURIComponent(row.name), "PATCH", {
					memoryGb: memory.getValue(), storageGb: storage.getValue(),
					performanceClass: performanceClass.getSelectedKey(), nseEnabled: nse.getSelected(), ecnNodes: ecn.getValue()
				}), "instanceUpdated", [row.name]);
			}.bind(this));
		},

		onStart: function (event) {
			const row = this.rowOf(event);
			this.run(this.api("/api/v1/cloud/instances/" + encodeURIComponent(row.name) + "/start", "POST"), "instanceStarted", [row.name]);
		},

		onStop: function (event) {
			const row = this.rowOf(event);
			this.confirm("stopInstanceConfirm", [row.name]).then(function () {
				this.run(this.api("/api/v1/cloud/instances/" + encodeURIComponent(row.name) + "/stop", "POST"), "instanceStopped", [row.name]);
			}.bind(this));
		},

		onDelete: function (event) {
			const row = this.rowOf(event);
			this.confirm("deleteInstanceConfirm", [row.name]).then(function () {
				this.run(this.api("/api/v1/cloud/instances/" + encodeURIComponent(row.name), "DELETE"), "instanceDeleted", [row.name]);
			}.bind(this));
		},

		onAdvisors: function (event) {
			const row = this.rowOf(event);
			this.api("/api/v1/cloud/instances/" + encodeURIComponent(row.name) + "/advisors").then(function (list) {
				const text = list.length ? list.map(function (r) {
					return "• [" + r.severity + "] " + r.title + "\n" + r.detail;
				}).join("\n\n") : this.text("noInstanceRecommendations");
				MessageBox.information(text, { title: this.text("advisorsFor", [row.name]) });
			}.bind(this), this.fail.bind(this));
		}
	});
});
