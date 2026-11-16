sap.ui.define([
  "sap/ui/test/Opa5",
  "sap/ui/test/actions/Press",
  "sap/ui/test/matchers/Properties"
], function (Opa5, Press, Properties) {
  "use strict";

  var sViewName = "ServiceDetail";

  Opa5.createPageObjects({
    onTheServiceDetailPage: {
      actions: {
        iPressBack: function () {
          return this.waitFor({
            id: "servicePage",
            viewName: sViewName,
            actions: new Press({ idSuffix: "navButton" }),
            errorMessage: "No back button on the detail page"
          });
        }
      },
      assertions: {
        iSeeTheTitle: function (sName) {
          return this.waitFor({
            id: "servicePage",
            viewName: sViewName,
            matchers: new Properties({ title: sName }),
            success: function () {
              Opa5.assert.ok(true, "Detail page of " + sName + " is shown");
            },
            errorMessage: "Detail page of " + sName + " not shown"
          });
        }
      }
    }
  });
});
