sap.ui.define([
  "neko/platform/controller/BaseController"
], function (BaseController) {
  "use strict";

  return BaseController.extend("neko.platform.controller.App", {
    onInit: function () {
      this.getView().addStyleClass(this.getOwnerComponent().getContentDensityClass());
    }
  });
});
