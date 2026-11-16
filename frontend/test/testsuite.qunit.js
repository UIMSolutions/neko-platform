sap.ui.define(function () {
  "use strict";

  return {
    name: "QUnit test suite for neko.platform",
    defaults: {
      page: "ui5://test-resources/neko/platform/Test.qunit.html?testsuite={suite}&test={name}",
      qunit: { version: 2 },
      sinon: { version: 4 },
      ui5: { theme: "sap_fiori_3" },
      loader: {
        paths: {
          "neko/platform": "../",
          "test-resources/neko/platform": "./"
        }
      }
    },
    tests: {
      "unit/unitTests": { title: "Unit tests for neko.platform" },
      // Needs the OData mock server: npm run start:mock, then open this suite.
      "integration/opaTests": { title: "Integration tests for neko.platform" }
    }
  };
});
