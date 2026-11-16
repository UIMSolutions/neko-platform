sap.ui.define([
  "sap/ui/core/library"
], function (coreLibrary) {
  "use strict";

  var ValueState = coreLibrary.ValueState;

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

    /** Translate an enum value via i18n ("status.active"), falling back to the raw value. */
    enumText: function (sPrefix, sValue) {
      if (!sValue) {
        return "";
      }
      var oBundle = this.getOwnerComponent().getModel("i18n").getResourceBundle();
      var sKey = sPrefix + "." + sValue;
      return oBundle.hasText(sKey) ? oBundle.getText(sKey) : sValue;
    },

    isOutbound: function (sDirection) {
      return sDirection === "outbound";
    },

    checksumShort: function (sChecksum) {
      return sChecksum ? sChecksum.substring(0, 12) + "…" : "";
    }
  };
});
