neko.ui.define([
  "neko/ui/test/Opa5",
  "./arrangements/Startup",
  "./NavigationJourney"
], function (Opa5, Startup) {
  "use strict";

  Opa5.extendConfig({
    arrangements: new Startup(),
    viewNamespace: "neko.platform.view.",
    autoWait: true
  });
});
