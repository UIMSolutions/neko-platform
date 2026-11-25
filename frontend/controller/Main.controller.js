neko.ui.define([
  "neko/platform/controller/BaseController",
  "neko/platform/model/models",
  "neko/ui/model/Filter",
  "neko/ui/model/FilterOperator",
  "neko/m/MessageBox",
  "neko/m/library"
], function (BaseController, models, Filter, FilterOperator, MessageBox, mobileLibrary) {
  "use strict";

  var URLHelper = mobileLibrary.URLHelper;

  return BaseController.extend("neko.platform.controller.Main", {
    onInit: function () {
      // Overview singleton = binding context of the whole view (header, tab counts, buttons).
      // ExportTargets is only needed by the export dialog, so select it explicitly.
      this.getView().bindElement({ path: "/Overview", parameters: { $select: "ExportTargets" } });
      this.getRouter().getRoute("main").attachPatternMatched(this._onRouteMatched, this);
    },

    _onRouteMatched: function (oEvent) {
      var sTab = (oEvent.getParameter("arguments") || {}).tab;
      this.byId("tabs").setSelectedKey(sTab === "transfers" ? "transfers" : "services");
    },

    onTabSelect: function (oEvent) {
      this.getRouter().navTo("main", { tab: oEvent.getParameter("key") }, true);
    },

    onRefresh: function () {
      this._refresh();
    },

    _refresh: function () {
      this.getView().getElementBinding().refresh();
      this.byId("servicesTable").getBinding("items").refresh();
      this.byId("transfersTable").getBinding("items").refresh();
    },

    // ── Services ────────────────────────────────────────────────────────────

    onFilterServices: function () {
      var aFilters = [];
      var sQuery = this.byId("serviceSearch").getValue();
      var sStatus = this.byId("statusFilter").getSelectedKey();
      if (sQuery) {
        aFilters.push(new Filter("Name", FilterOperator.Contains, sQuery));
      }
      if (sStatus) {
        aFilters.push(new Filter("Status", FilterOperator.EQ, sStatus));
      }
      this.byId("servicesTable").getBinding("items").filter(aFilters);
    },

    onServicePress: function (oEvent) {
      var sId = oEvent.getSource().getBindingContext().getProperty("ID");
      this.getRouter().navTo("service", { id: encodeURIComponent(sId) });
    },

    onOpenRegister: function () {
      this.getModel("ui").setProperty("/register", models.emptyRegisterForm());
      this._openDialog("RegisterServiceDialog").catch(this.showError.bind(this));
    },

    onConfirmRegister: function () {
      var oForm = this.getModel("ui").getProperty("/register");
      var oBinding = this.byId("servicesTable").getBinding("items");
      var oContext = oBinding.create({
        Name: oForm.Name.trim(),
        Description: oForm.Description,
        Classification: oForm.Classification,
        BaseUrl: oForm.BaseUrl,
        HealthPath: oForm.HealthPath
      });

      var oDone = oContext.created().then(function () {
        if (oForm.Activate) {
          return this.callAction("ActivateService", { ID: oContext.getProperty("ID") });
        }
      }.bind(this));

      this.withBusy(oDone, "register.success").then(function () {
        this._closeDialog("RegisterServiceDialog");
        this._refresh();
      }.bind(this)).catch(function () {
        // A failed POST leaves a transient row behind; discard it.
        if (oContext.isTransient && oContext.isTransient()) {
          oContext.delete().catch(function () { /* already gone */ });
        }
      });
    },

    // ── Transfers ───────────────────────────────────────────────────────────

    onOpenExport: function () {
      var oUi = this.getModel("ui");
      // A collection is not primitive: getProperty/requestProperty refuse it, requestObject works.
      this.getView().getBindingContext().requestObject("ExportTargets").then(function (aTargets) {
        aTargets = aTargets || [];
        oUi.setProperty("/exportTargets", aTargets.map(function (s) { return { key: s }; }));
        oUi.setProperty("/exportForm", models.emptyExportForm(aTargets[0]));
        return this._openDialog("ExportPackageDialog");
      }.bind(this)).catch(this.showError.bind(this));
    },

    onConfirmExport: function () {
      var oForm = this.getModel("ui").getProperty("/exportForm");
      this.withBusy(this.callAction("ExportPackage", {
        Name: oForm.Name,
        TargetDomain: oForm.TargetDomain,
        Payload: oForm.Payload
      })).then(function (oTransfer) {
        this._closeDialog("ExportPackageDialog");
        this._refresh();
        MessageBox.success(this.getText("export.success", [oTransfer.Name, oTransfer.TargetDomain]), {
          actions: [this.getText("transfers.download"), MessageBox.Action.CLOSE],
          emphasizedAction: this.getText("transfers.download"),
          onClose: function (sAction) {
            if (sAction === this.getText("transfers.download")) {
              URLHelper.redirect(this.packageUrl(oTransfer.ID), true);
            }
          }.bind(this)
        });
      }.bind(this)).catch(function () { /* reported by withBusy */ });
    },

    onDownload: function (oEvent) {
      var sId = oEvent.getSource().getBindingContext().getProperty("ID");
      URLHelper.redirect(this.packageUrl(sId), true);
    },

    onOpenImport: function () {
      this.getModel("ui").setProperty("/importForm", models.emptyImportForm());
      this._openDialog("ImportPackageDialog").then(function () {
        this.byId("importFile").clear();
      }.bind(this)).catch(this.showError.bind(this));
    },

    onImportFileChange: function (oEvent) {
      var oFile = (oEvent.getParameter("files") || [])[0];
      if (!oFile) {
        return;
      }
      var oUi = this.getModel("ui");
      var oReader = new FileReader();
      oReader.onload = function () {
        oUi.setProperty("/importForm/FileName", oFile.name);
        oUi.setProperty("/importForm/Document", oReader.result);
      };
      oReader.onerror = function () {
        this.showError(oReader.error);
      }.bind(this);
      oReader.readAsText(oFile);
    },

    onConfirmImport: function () {
      var sDocument = this.getModel("ui").getProperty("/importForm/Document");
      this.withBusy(this.callAction("ImportPackage", { Document: sDocument }), "import.success")
        .then(function () {
          this._closeDialog("ImportPackageDialog");
        }.bind(this))
        .catch(function () { /* reported by withBusy; a refused package is still listed as rejected */ })
        .finally(this._refresh.bind(this));
    },

    // ── Dialog helpers ──────────────────────────────────────────────────────

    _openDialog: function (sName) {
      this._dialogs = this._dialogs || {};
      if (!this._dialogs[sName]) {
        this._dialogs[sName] = this.loadFragment({ name: "neko.platform.fragment." + sName });
      }
      return this._dialogs[sName].then(function (oDialog) {
        oDialog.open();
        return oDialog;
      });
    },

    _closeDialog: function (sName) {
      if (this._dialogs && this._dialogs[sName]) {
        this._dialogs[sName].then(function (oDialog) { oDialog.close(); });
      }
    },

    onCloseDialog: function (oEvent) {
      var oControl = oEvent.getSource();
      while (oControl && !oControl.isA("neko.m.Dialog")) {
        oControl = oControl.getParent();
      }
      if (oControl) {
        oControl.close();
      }
    }
  });
});
