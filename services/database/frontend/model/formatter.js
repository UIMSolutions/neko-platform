sap.ui.define([], function () {
	"use strict";

	/** Formatierer der Cloud-Seiten; ohne UI5-Abhängigkeiten, damit sie sich in QUnit einzeln prüfen lassen. */
	return {
		/** Schwere einer Empfehlung als ValueState. */
		severityState: function (severity) {
			switch (severity) {
				case "high": return "Error";
				case "medium": return "Warning";
				case "low": return "Information";
				default: return "None";
			}
		},

		/** Zustand einer Instanz als ValueState. */
		statusState: function (status) {
			switch (status) {
				case "running": return "Success";
				case "stopped": return "Warning";
				case "error": return "Error";
				default: return "None";
			}
		},

		/** Art eines Trace-Eintrags als ValueState. */
		traceState: function (kind) {
			switch (kind) {
				case "error": return "Error";
				case "violation": return "Warning";
				case "expensive": return "Information";
				default: return "None";
			}
		},

		bytes: function (value) {
			const n = Number(value) || 0;
			const units = ["B", "KiB", "MiB", "GiB", "TiB"];
			let i = 0;
			let v = n;
			while (v >= 1024 && i < units.length - 1) {
				v /= 1024;
				i++;
			}
			return (i === 0 ? String(v) : v.toFixed(1)) + " " + units[i];
		},

		ms: function (value) {
			const n = Number(value) || 0;
			return n >= 1000 ? (n / 1000).toFixed(2) + " s" : n.toFixed(n < 10 ? 2 : 0) + " ms";
		},

		percent: function (value) {
			return (Number(value) || 0).toFixed(1) + " %";
		},

		/** Größe einer Instanz: "64 GB · 8 vCPU · 256 GB". */
		sizing: function (memory, vcpus, storage) {
			return memory + " GB · " + vcpus + " vCPU · " + storage + " GB";
		}
	};
});
