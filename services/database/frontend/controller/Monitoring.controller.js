sap.ui.define([
	"hdb/client/controller/BaseController",
	"sap/m/Button",
	"sap/m/CheckBox",
	"sap/m/Dialog",
	"sap/m/Label",
	"sap/m/MessageBox",
	"sap/m/StepInput",
	"sap/ui/layout/form/SimpleForm",
	"sap/ui/model/Filter",
	"sap/ui/model/FilterOperator"
], function (BaseController, Button, CheckBox, Dialog, Label, MessageBox, StepInput, SimpleForm, Filter, FilterOperator) {
	"use strict";

	/** Überwachung: Kennzahlen aus der REST-API, Trace aus OData (/odata/v4/cloud/Traces). */
	return BaseController.extend("hdb.client.controller.Monitoring", {
		route: "monitoring",

		onInit: function () {
			BaseController.prototype.onInit.apply(this, arguments);
			this.getView().getModel("view").setData({ busy: false, overview: {}, last: {}, kind: "", summary: "" });
		},

		onShow: function () {
			this.api("/api/v1/monitoring").then(function (o) {
				const view = this.getView().getModel("view");
				view.setProperty("/overview", o);
				view.setProperty("/last", o.samples.length ? o.samples[o.samples.length - 1] : {});
			}.bind(this), this.fail.bind(this));
			this.refreshList();
		},

		onKind: function (event) {
			const key = event.getParameter("item").getKey();
			this.byId("list").getBinding("items").filter(key ? [new Filter("kind", FilterOperator.EQ, key)] : []);
		},

		onSummary: function () {
			this.api("/api/v1/monitoring/issues").then(function (s) {
				const view = this.getView().getModel("view");
				view.setProperty("/summary", s.text);
				view.setProperty("/summaryErrors", s.errors + s.violations);
			}.bind(this), this.fail.bind(this));
		},

		onSettings: function () {
			this.api("/api/v1/monitoring/trace-settings").then(function (s) {
				const sql = new CheckBox({ text: this.text("sqlTraceAll"), selected: s.sqlTrace });
				const errors = new CheckBox({ text: this.text("traceErrors"), selected: s.traceErrors });
				const threshold = new StepInput({ value: s.expensiveThresholdMs, min: 0, max: 3600000, step: 100 });
				const max = new StepInput({ value: s.maxEntries, min: 1, max: 100000, step: 100 });
				const dialog = new Dialog({
					title: this.text("traceSettings"),
					contentWidth: "28rem",
					content: [new SimpleForm({ editable: true, layout: "ColumnLayout", content: [
						new Label({ text: "" }), sql,
						new Label({ text: "" }), errors,
						new Label({ text: this.text("expensiveThreshold") }), threshold,
						new Label({ text: this.text("maxEntries") }), max
					] })],
					beginButton: new Button({ text: this.text("save"), type: "Emphasized", press: function () {
						this.run(this.api("/api/v1/monitoring/trace-settings", "PUT", {
							sqlTrace: sql.getSelected(), traceErrors: errors.getSelected(),
							expensiveThresholdMs: threshold.getValue(), maxEntries: max.getValue()
						}), "settingsSaved").then(function () {
							dialog.close();
						});
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
			}.bind(this), this.fail.bind(this));
		},

		onClear: function () {
			this.confirm("clearTraceConfirm").then(function () {
				this.run(this.api("/api/v1/monitoring/traces", "DELETE"), "traceCleared");
			}.bind(this));
		}
	});
});
