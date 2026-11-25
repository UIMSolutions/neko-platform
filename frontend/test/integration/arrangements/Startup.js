neko.ui.define([
  "neko/ui/test/Opa5"
], function (Opa5) {
  "use strict";

  return Opa5.extend("neko.platform.test.integration.arrangements.Startup", {
    /** Start the component in an iframe-free container (data from the mock server). */
    iStartMyApp: function (oOptions) {
      oOptions = oOptions || {};
      this.iStartMyUIComponent({
        componentConfig: { name: "neko.platform", async: true },
        hash: oOptions.hash || "",
        autoWait: true
      });
    }
  });
});
