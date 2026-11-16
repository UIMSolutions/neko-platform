sap.ui.define([
  "sap/ui/core/library"
], function (coreLibrary) {
  "use strict";

  var ValueState = coreLibrary.ValueState;

  function enumText(oController, sPrefix, sValue) {
    if (!sValue) {
      return "";
    }
    var oComponent = oController && oController.getOwnerComponent && oController.getOwnerComponent();
    var oBundle = oComponent && oComponent.getModel("i18n").getResourceBundle();
    // getText(…, true) searches the whole fallback chain (en → base) and returns
    // undefined instead of the key; hasText would only check the first bundle.
    var sText = oBundle && oBundle.getText(sPrefix + "." + sValue, undefined, true);
    return sText === undefined ? sValue : sText;
  }

  return {
    /** Semantic colour of a service life-cycle status. */
    serviceStatusState: function (sStatus) {
      switch (sStatus) {
        case "active": return ValueState.Success;
        case "suspended": return ValueState.Warning;
        case "retired": return ValueState.Error;
        default: return ValueState.Information;
      }
    },

    healthState: function (sHealth) {
      switch (sHealth) {
        case "up": return ValueState.Success;
        case "down": return ValueState.Error;
        default: return ValueState.None;
      }
    },

    healthIcon: function (sHealth) {
      switch (sHealth) {
        case "up": return "sap-icon://status-positive";
        case "down": return "sap-icon://status-negative";
        default: return "sap-icon://status-inactive";
      }
    },

    transferStatusState: function (sStatus) {
      switch (sStatus) {
        case "exported":
        case "imported": return ValueState.Success;
        case "rejected": return ValueState.Error;
        default: return ValueState.None;
      }
    },

    directionIcon: function (sDirection) {
      return sDirection === "outbound" ? "sap-icon://outbox" : "sap-icon://inbox";
    },

    /** Higher classification → stronger colour. */
    domainState: function (sDomain) {
      switch (sDomain) {
        case "open": return ValueState.Success;
        case "restricted": return ValueState.Information;
        case "confidential": return ValueState.Warning;
        case "secret": return ValueState.Error;
        default: return ValueState.None;
      }
    },

    /** 1536 → "1.5 KB" */
    bytes: function (iBytes) {
      if (iBytes === null || iBytes === undefined) {
        return "";
      }
      var aUnits = ["B", "KB", "MB", "GB"];
      var fValue = Number(iBytes);
      var i = 0;
      while (fValue >= 1024 && i < aUnits.length - 1) {
        fValue /= 1024;
        i++;
      }
      return (i === 0 ? fValue : fValue.toFixed(1)) + " " + aUnits[i];
    },

    /* Translated enum texts ("status.active" → "Active"); called with the controller as `this`. */
    serviceStatusText: function (sValue) {
      return enumText(this, "status", sValue);
    },

    healthText: function (sValue) {
      return enumText(this, "health", sValue);
    },

    transferStatusText: function (sValue) {
      return enumText(this, "transferStatus", sValue);
    },

    directionText: function (sValue) {
      return enumText(this, "direction", sValue);
    },

    domainText: function (sValue) {
      return enumText(this, "domain", sValue);
    },

    isOutbound: function (sDirection) {
      return sDirection === "outbound";
    },

    checksumShort: function (sChecksum) {
      return sChecksum ? sChecksum.substring(0, 12) + "…" : "";
    }
  };
});
