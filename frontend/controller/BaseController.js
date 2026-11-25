neko.ui.define([
  "neko/ui/core/mvc/Controller",
  "neko/ui/core/routing/History",
  "neko/ui/core/UIComponent",
  "neko/m/MessageBox",
  "neko/m/MessageToast",
  "neko/platform/model/formatter"
], function (Controller, History, UIComponent, MessageBox, MessageToast, formatter) {
  "use strict";

  return Controller.extend("neko.platform.controller.BaseController", {
    formatter: formatter,

    getRouter: function () {
      return UIComponent.getRouterFor(this);
    },

    getModel: function (sName) {
      return this.getView().getModel(sName);
    },

    getText: function (sKey, aArgs) {
      return this.getOwnerComponent().getModel("i18n").getResourceBundle().getText(sKey, aArgs);
    },

    onNavBack: function () {
      if (History.getInstance().getPreviousHash() !== undefined) {
        window.history.go(-1);
      } else {
        this.getRouter().navTo("main", {}, true);
      }
    },

    /**
     * Invoke an unbound OData action (ActionImport) and resolve with the
     * returned entity as plain object.
     */
    callAction: function (sName, mParameters) {
      var oOperation = this.getModel().bindContext("/" + sName + "(...)");
      Object.keys(mParameters).forEach(function (sKey) {
        oOperation.setParameter(sKey, mParameters[sKey]);
      });
      return oOperation.execute().then(function () {
        return oOperation.getBoundContext().getObject();
      });
    },

    /** Wrap a promise with the busy indicator and uniform error handling. */
    withBusy: function (oPromise, sSuccessKey) {
      var oUi = this.getModel("ui");
      oUi.setProperty("/busy", true);
      return oPromise.then(function (vResult) {
        if (sSuccessKey) {
          MessageToast.show(this.getText(sSuccessKey));
        }
        return vResult;
      }.bind(this)).catch(function (oError) {
        this.showError(oError);
        throw oError;
      }.bind(this)).finally(function () {
        oUi.setProperty("/busy", false);
      });
    },

    showError: function (oError) {
      var sMessage = (oError && oError.error && oError.error.message) || (oError && oError.message) || String(oError);
      MessageBox.error(sMessage, { title: this.getText("error.title") });
    },

    /** URL of a transfer document (REST); relative, so it also works behind the approuter. */
    packageUrl: function (sTransferId) {
      return "rest/v1/transfers/" + encodeURIComponent(sTransferId) + "/package";
    }
  });
});
