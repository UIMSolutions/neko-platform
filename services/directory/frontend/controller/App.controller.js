sap.ui.define([
  "uim/identitydirectory/controller/BaseController"
], function (BaseController) {
  "use strict";

  var GROUPS = ["directory", "security"];

  return BaseController.extend("uim.identitydirectory.controller.App", {
    onInit: function () {
      this.getView().addStyleClass(this.getOwnerComponent().getContentDensityClass());
      this.getRouter().attachRouteMatched(function (oEvent) {
        var oArgs = oEvent.getParameter("arguments") || {};
        var sName = oEvent.getParameter("name");
        this.getModel("ui").setProperty("/selectedNav",
          sName === "resource" ? oArgs.set : sName === "user" ? "Users" : "overview");
      }, this);
    },

    navText: function (sKey) {
      return sKey ? this.getText(sKey) : "";
    },

    setTitle: function (sSet) {
      return sSet ? this.getText("set_" + sSet) : "";
    },

    onToggleSide: function () {
      var oUi = this.getModel("ui");
      oUi.setProperty("/sideExpanded", !oUi.getProperty("/sideExpanded"));
    },

    onNavSelect: function (oEvent) {
      var oItem = oEvent.getParameter("item");
      var sKey = oItem.getKey();
      if (GROUPS.indexOf(sKey) >= 0) {
        oItem.setExpanded(!oItem.getExpanded());
        return;
      }
      if (sKey === "overview") {
        this.getRouter().navTo("overview");
      } else {
        this.getRouter().navTo("resource", { set: sKey });
      }
    },

    onRefresh: function () {
      this.getModel().refresh();
    },

    /** POST /SeedContent — predefined password policies and the enterprise user schema. */
    onSeed: function () {
      this.run(this.service().invoke("SeedContent"), null).then(function (oResult) {
        if (oResult) {
          this.showToast("seeded", [oResult.created, oResult.skipped]);
        }
      }.bind(this));
    },

    /** POST /RunHousekeeping — automatic unlock, password / client expiry, dynamic groups, audit retention. */
    onHousekeeping: function () {
      this.run(this.service().invoke("RunHousekeeping"), null).then(function (oResult) {
        if (oResult) {
          this.showToast("housekept", [oResult.changed, oResult.examined]);
        }
      }.bind(this));
    },

    showToast: function (sKey, aArgs) {
      sap.ui.require(["sap/m/MessageToast"], function (MessageToast) {
        MessageToast.show(this.getText(sKey, aArgs));
      }.bind(this));
    }
  });
});
