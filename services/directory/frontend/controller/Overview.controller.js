sap.ui.define([
  "uim/identitydirectory/controller/BaseController"
], function (BaseController) {
  "use strict";

  return BaseController.extend("uim.identitydirectory.controller.Overview", {
    onInit: function () {
      this.getRouter().getRoute("overview").attachPatternMatched(function () {
        var oBinding = this.byId("kpiHeader").getElementBinding();
        if (oBinding) {
          oBinding.refresh();
        }
      }, this);
    },

    onTile: function (oEvent) {
      this.getRouter().navTo("resource", { set: oEvent.getSource().data("set") });
    }
  });
});
