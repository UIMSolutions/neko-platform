sap.ui.define([
	"hdb/client/controller/BaseController",
	"sap/m/Button",
	"sap/m/Column",
	"sap/m/ColumnListItem",
	"sap/m/Dialog",
	"sap/m/Input",
	"sap/m/Label",
	"sap/m/Select",
	"sap/m/Table",
	"sap/m/Text",
	"sap/ui/core/Item",
	"sap/ui/layout/form/SimpleForm",
	"sap/ui/model/json/JSONModel"
], function (BaseController, Button, Column, ColumnListItem, Dialog, Input, Label, Select, Table, Text, Item, SimpleForm, JSONModel) {
	"use strict";

	/** "col:LABEL, col2" → Attribute; "sum(amount):REVENUE" → Kennzahlen. */
	function parseAttributes(text) {
		return text.split(",").map(function (part) {
			const p = part.trim().split(":");
			return p[0] ? { column: p[0].trim(), label: (p[1] || "").trim() } : null;
		}).filter(Boolean);
	}

	function parseMeasures(text) {
		return text.split(",").map(function (part) {
			const p = part.trim().split(":");
			const m = /^(\w+)\(([\w.]+)\)$/.exec((p[0] || "").trim());
			return m ? { aggregation: m[1], column: m[2], label: (p[1] || "").trim() } : null;
		}).filter(Boolean);
	}

	/** Calculation Views: Definition anlegen, Vorschau über REST, Abfrage als OData-Entity-Set CV_<name>. */
	return BaseController.extend("hdb.client.controller.CalcViews", {
		route: "views",

		onCreate: function () {
			const name = new Input({ required: true });
			const label = new Input();
			const base = new Select({
				width: "100%",
				items: (this.getOwnerComponent().getModel("app").getProperty("/sets") || []).map(function (set) {
					return new Item({ key: set.name, text: set.name });
				})
			});
			const attributes = new Input({ placeholder: "region:REGION, segment" });
			const measures = new Input({ placeholder: "sum(amount):REVENUE, count(id):ORDERS" });
			const filter = new Input({ placeholder: "status = 'paid'" });
			const dialog = new Dialog({
				title: this.text("createView"),
				contentWidth: "34rem",
				content: [new SimpleForm({ editable: true, layout: "ColumnLayout", content: [
					new Label({ text: this.text("name"), required: true }), name,
					new Label({ text: this.text("label") }), label,
					new Label({ text: this.text("baseTable"), required: true }), base,
					new Label({ text: this.text("attributes") }), attributes,
					new Label({ text: this.text("measures") }), measures,
					new Label({ text: this.text("filter") }), filter
				] })],
				beginButton: new Button({ text: this.text("create"), type: "Emphasized", press: function () {
					this.run(this.api("/api/v1/views", "POST", {
						name: name.getValue().trim(), label: label.getValue(), baseTable: base.getSelectedKey(),
						attributes: parseAttributes(attributes.getValue()), measures: parseMeasures(measures.getValue()),
						filter: filter.getValue()
					}), "viewSaved").then(function () {
						dialog.close();
					}, function () { /* Meldung zeigt run() */ });
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

		onPreview: function (event) {
			const row = this.rowOf(event);
			this.api("/api/v1/views/" + encodeURIComponent(row.name) + "/data?top=100").then(function (data) {
				const table = new Table({
					columns: data.columns.map(function (c) {
						return new Column({ header: new Text({ text: c }) });
					}),
					items: {
						path: "/rows",
						template: new ColumnListItem({ cells: data.columns.map(function (c) {
							return new Text({ text: "{" + c + "}" });
						}) })
					}
				});
				table.setModel(new JSONModel(data));
				const dialog = new Dialog({
					title: row.label || row.name,
					contentWidth: "48rem",
					content: [table],
					endButton: new Button({ text: this.text("close"), press: function () {
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

		onDelete: function (event) {
			const row = this.rowOf(event);
			this.confirm("deleteConfirmNamed", [row.name]).then(function () {
				this.run(this.api("/api/v1/views/" + encodeURIComponent(row.name), "DELETE"), "deleted");
			}.bind(this));
		}
	});
});
