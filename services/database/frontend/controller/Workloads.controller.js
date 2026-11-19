sap.ui.define([
	"hdb/client/controller/BaseController",
	"sap/m/Button",
	"sap/m/CheckBox",
	"sap/m/Dialog",
	"sap/m/Input",
	"sap/m/Label",
	"sap/m/StepInput",
	"sap/ui/layout/form/SimpleForm"
], function (BaseController, Button, CheckBox, Dialog, Input, Label, StepInput, SimpleForm) {
	"use strict";

	/** Workload-Klassen und Zuordnungen; durchgesetzt werden sie bei jeder Anweisung auf dem Server. */
	return BaseController.extend("hdb.client.controller.Workloads", {
		route: "workloads",

		refreshList: function () {
			BaseController.prototype.refreshList.apply(this, arguments);
			const binding = this.byId("mappings").getBinding("items");
			if (binding) {
				binding.refresh();
			}
		},

		_form: function (title, content, onOk) {
			const dialog = new Dialog({
				title: title,
				contentWidth: "28rem",
				content: [new SimpleForm({ editable: true, layout: "ColumnLayout", content: content })],
				beginButton: new Button({ text: this.text("save"), type: "Emphasized", press: function () {
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

		onCreateClass: function () {
			const name = new Input({ required: true });
			const priority = new StepInput({ value: 5, min: 0, max: 9 });
			const timeout = new StepInput({ value: 0, min: 0, max: 86400 });
			const memory = new StepInput({ value: 0, min: 0, max: 1048576, step: 64 });
			const limit = new StepInput({ value: 0, min: 0, max: 10000 });
			const enabled = new CheckBox({ text: this.text("enabled"), selected: true });
			this._form(this.text("createWorkloadClass"), [
				new Label({ text: this.text("name"), required: true }), name,
				new Label({ text: this.text("priority") }), priority,
				new Label({ text: this.text("timeoutSeconds") }), timeout,
				new Label({ text: this.text("memoryLimitMb") }), memory,
				new Label({ text: this.text("statementLimit") }), limit,
				new Label({ text: "" }), enabled
			], function () {
				return this.run(this.api("/api/v1/workloads/classes/" + encodeURIComponent(name.getValue().trim()), "PUT", {
					priority: priority.getValue(), statementTimeoutSeconds: timeout.getValue(),
					statementMemoryLimitMb: memory.getValue(), totalStatementLimit: limit.getValue(), enabled: enabled.getSelected()
				}), "workloadSaved");
			}.bind(this));
		},

		onCreateMapping: function () {
			const name = new Input({ required: true });
			const workloadClass = new Input({ required: true });
			const user = new Input();
			const role = new Input();
			this._form(this.text("createMapping"), [
				new Label({ text: this.text("name"), required: true }), name,
				new Label({ text: this.text("workloadClass"), required: true }), workloadClass,
				new Label({ text: this.text("user") }), user,
				new Label({ text: this.text("role") }), role
			], function () {
				return this.run(this.api("/api/v1/workloads/mappings/" + encodeURIComponent(name.getValue().trim()), "PUT", {
					workloadClass: workloadClass.getValue(), userName: user.getValue(), roleName: role.getValue()
				}), "workloadSaved");
			}.bind(this));
		},

		onDeleteClass: function (event) {
			const row = this.rowOf(event);
			this.confirm("deleteConfirmNamed", [row.name]).then(function () {
				this.run(this.api("/api/v1/workloads/classes/" + encodeURIComponent(row.name), "DELETE"), "deleted");
			}.bind(this));
		},

		onDeleteMapping: function (event) {
			const row = this.rowOf(event);
			this.confirm("deleteConfirmNamed", [row.name]).then(function () {
				this.run(this.api("/api/v1/workloads/mappings/" + encodeURIComponent(row.name), "DELETE"), "deleted");
			}.bind(this));
		}
	});
});
