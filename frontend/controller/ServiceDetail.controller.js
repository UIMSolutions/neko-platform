neko.ui.define([
  "neko/platform/controller/BaseController",
  "neko/m/MessageBox"
], function (BaseController, MessageBox) {
  "use strict";

  return BaseController.extend("neko.platform.controller.ServiceDetail", {
    onInit: function () {
      this.getRouter().getRoute("service").attachPatternMatched(this._onRouteMatched, this);
    },

    _onRouteMatched: function (oEvent) {
      var sId = decodeURIComponent(oEvent.getParameter("arguments").id);
      this.getModel("ui").setProperty("/editMode", false);
      // OData key literal: single quotes are escaped by doubling.
      this.getView().bindElement({ path: "/Services('" + sId.replace(/'/g, "''") + "')" });
    },

    _serviceId: function () {
      return this.getView().getBindingContext().getProperty("ID");
    },

    _run: function (sAction, sSuccessKey) {
      return this.withBusy(this.callAction(sAction, { ID: this._serviceId() }), sSuccessKey)
        .then(function () {
          this.getView().getElementBinding().refresh();
        }.bind(this))
        .catch(function () { /* reported by withBusy */ });
    },

    onActivate: function () {
      this._run("ActivateService", "action.activated");
    },

    onSuspend: function () {
      this._run("SuspendService", "action.suspended");
    },

    onCheckHealth: function () {
      this._run("CheckServiceHealth", "action.checked");
    },

    onRetire: function () {
      var sName = this.getView().getBindingContext().getProperty("Name");
      MessageBox.confirm(this.getText("action.retireConfirm", [sName]), {
        emphasizedAction: MessageBox.Action.OK,
        onClose: function (sAction) {
          if (sAction === MessageBox.Action.OK) {
            this._run("RetireService", "action.retired");
          }
        }.bind(this)
      });
    },

    onDelete: function () {
      var oContext = this.getView().getBindingContext();
      MessageBox.confirm(this.getText("action.deleteConfirm", [oContext.getProperty("Name")]), {
        onClose: function (sAction) {
          if (sAction !== MessageBox.Action.OK) {
            return;
          }
          this.withBusy(oContext.delete("$direct"), "action.deleted")
            .then(this.onNavBack.bind(this))
            .catch(function () { /* reported by withBusy */ });
        }.bind(this)
      });
    }
  });
});
