neko.ui.define([
  "neko/ui/model/json/JSONModel",
  "neko/ui/Device"
], function (JSONModel, Device) {
  "use strict";

  return {
    createDeviceModel: function () {
      var oModel = new JSONModel(Device);
      oModel.setDefaultBindingMode("OneWay");
      return oModel;
    },

    /** View state shared by all views (busy flags, edit mode, dialog forms). */
    createViewModel: function () {
      return new JSONModel({
        busy: false,
        editMode: false,
        register: {},
        exportForm: {},
        importForm: {}
      });
    },

    emptyRegisterForm: function () {
      return { Name: "", Description: "", Classification: "", BaseUrl: "", HealthPath: "/health", Activate: true };
    },

    emptyExportForm: function (sTarget) {
      return { Name: "", TargetDomain: sTarget || "", Payload: "" };
    },

    emptyImportForm: function () {
      return { FileName: "", Document: "" };
    }
  };
});
