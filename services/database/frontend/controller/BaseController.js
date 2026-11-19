sap.ui.define([
	"sap/ui/core/mvc/Controller",
	"sap/m/MessageBox",
	"sap/m/MessageToast",
	"sap/ui/model/json/JSONModel",
	"hdb/client/model/formatter"
], function (Controller, MessageBox, MessageToast, JSONModel, formatter) {
	"use strict";

	/**
	 * Grundlage der Cloud-Seiten: Listen kommen aus dem OData-V4-Modell "cloud" (/odata/v4/cloud), Aktionen
	 * laufen über die REST-API (/api/v1). Nach einer Aktion wird die Liste neu gelesen.
	 */
	return Controller.extend("hdb.client.controller.BaseController", {
		formatter: formatter,

		/** Route, deren Aufruf die Seite neu lädt; Unterklassen setzen sie. */
		route: "",

		onInit: function () {
			this.getView().setModel(new JSONModel({ busy: false }), "view");
			if (this.route) {
				this.getOwnerComponent().getRouter().getRoute(this.route).attachPatternMatched(this.onShow, this);
			}
		},

		/** Beim Öffnen der Seite. */
		onShow: function () {
			this.refreshList();
		},

		text: function (key, args) {
			return this.getOwnerComponent().getModel("i18n").getResourceBundle().getText(key, args);
		},

		/** REST mit Token; liefert JSON oder null bei 204. */
		api: function (url, method, body) {
			const options = { method: method || "GET" };
			if (body !== undefined) {
				options.headers = { "Content-Type": "application/json" };
				options.body = JSON.stringify(body);
			}
			return this.getOwnerComponent().authFetch(url, options).then(function (response) {
				return response.status === 204 ? null : response.json();
			});
		},

		/** Führt eine Aktion aus, zeigt Erfolg oder Fehler und liest die Liste neu. */
		run: function (promise, successKey, args) {
			const view = this.getView().getModel("view");
			view.setProperty("/busy", true);
			return promise.then(function (result) {
				view.setProperty("/busy", false);
				if (successKey) {
					MessageToast.show(this.text(successKey, args));
				}
				this.refreshList();
				return result;
			}.bind(this), function (error) {
				view.setProperty("/busy", false);
				this.fail(error);
				throw error;
			}.bind(this));
		},

		fail: function (error) {
			if (this.getOwnerComponent().handleError(error)) {
				return;
			}
			MessageBox.error(error.message || String(error));
		},

		/**
		 * Liest die Liste der Seite neu (Tabelle mit der Id "list"). Die Bindungen beginnen angehalten
		 * (suspended), damit keine Seite liest, bevor sie geöffnet wird: Systemadministratoren und Mandanten
		 * sehen verschiedene Entity Sets.
		 */
		refreshList: function () {
			this.refreshTable("list");
		},

		refreshTable: function (id) {
			const table = this.byId(id);
			const binding = table && table.getBinding("items");
			if (!binding) {
				return;
			}
			if (binding.isSuspended && binding.isSuspended()) {
				binding.resume();
			} else if (binding.refresh) {
				binding.refresh();
			}
		},

		/** Kontext der Zeile, auf deren Knopf gedrückt wurde. */
		rowOf: function (event, model) {
			return event.getSource().getBindingContext(model || "cloud").getObject();
		},

		confirm: function (key, args) {
			return new Promise(function (resolve) {
				MessageBox.confirm(this.text(key, args), {
					onClose: function (action) {
						if (action === MessageBox.Action.OK) {
							resolve();
						}
					}
				});
			}.bind(this));
		},

		onRefresh: function () {
			this.onShow();
		},

		onClose: function () {
			this.getOwnerComponent().getRouter().navTo("home");
		}
	});
});
