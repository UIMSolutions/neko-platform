/*global QUnit */
neko.ui.define([
  "neko/ui/test/opaQunit",
  "./pages/Main",
  "./pages/ServiceDetail"
], function (opaTest) {
  "use strict";

  QUnit.module("Navigation");

  opaTest("The service catalogue is shown on start", function (Given, When, Then) {
    Given.iStartMyApp();
    Then.onTheMainPage.iSeeServices(3);
  });

  opaTest("Pressing a service opens its detail page", function (Given, When, Then) {
    When.onTheMainPage.iPressTheService("management");
    Then.onTheServiceDetailPage.iSeeTheTitle("management");
  });

  opaTest("Back navigation returns to the catalogue", function (Given, When, Then) {
    When.onTheServiceDetailPage.iPressBack();
    Then.onTheMainPage.iSeeServices(3);
    Then.iTeardownMyUIComponent();
  });
});
