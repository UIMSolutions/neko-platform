sap.ui.define([
  "sap/ui/test/Opa5",
  "sap/ui/test/actions/Press",
  "sap/ui/test/matchers/AggregationLengthEquals",
  "sap/ui/test/matchers/BindingPath",
  "sap/ui/test/matchers/Properties"
], function (Opa5, Press, AggregationLengthEquals, BindingPath, Properties) {
  "use strict";

  var sViewName = "Main";

  Opa5.createPageObjects({
    onTheMainPage: {
      actions: {
        iPressTheService: function (sName) {
          return this.waitFor({
            controlType: "sap.m.ObjectIdentifier",
            viewName: sViewName,
            matchers: new Properties({ title: sName }),
            success: function (aIdentifiers) {
              new Press().executeOn(aIdentifiers[0].getParent());
            },
            errorMessage: "Service " + sName + " not found"
          });
        }
      },
      assertions: {
        iSeeServices: function (iCount) {
          return this.waitFor({
            id: "servicesTable",
            viewName: sViewName,
            matchers: new AggregationLengthEquals({ name: "items", length: iCount }),
            success: function () {
              Opa5.assert.ok(true, "The catalogue shows " + iCount + " services");
            },
            errorMessage: "The catalogue does not show " + iCount + " services"
          });
        }
      }
    }
  });
});
