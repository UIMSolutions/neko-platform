// Neko Platform pages: dialogs, snackbar and theme switch for Beer CSS + htmx.
// Loaded as a file because the Content-Security-Policy forbids inline scripts.
(function () {
  "use strict";

  var THEME_KEY = "neko.theme";

  function readTheme() {
    try { return localStorage.getItem(THEME_KEY); } catch (e) { return null; }
  }

  function applyTheme(mode) {
    var body = document.body;
    body.classList.remove("light", "dark");
    if (mode === "light" || mode === "dark") body.classList.add(mode);
    var dark = mode ? mode === "dark" : window.matchMedia("(prefers-color-scheme: dark)").matches;
    document.querySelectorAll("[data-theme-toggle] i").forEach(function (icon) {
      icon.textContent = dark ? "light_mode" : "dark_mode";
    });
  }

  function toggleTheme() {
    var current = document.body.classList.contains("dark") ? "dark"
      : document.body.classList.contains("light") ? "light"
      : (window.matchMedia("(prefers-color-scheme: dark)").matches ? "dark" : "light");
    var next = current === "dark" ? "light" : "dark";
    try { localStorage.setItem(THEME_KEY, next); } catch (e) { /* private mode */ }
    applyTheme(next);
  }

  var snackbarTimer;
  function notify(message, isError) {
    var bar = document.getElementById("snackbar");
    if (!bar || !message) return;
    bar.querySelector("span").textContent = message;
    bar.querySelector("i").textContent = isError ? "error" : "check_circle";
    bar.classList.toggle("error", !!isError);
    bar.classList.add("active");
    clearTimeout(snackbarTimer);
    snackbarTimer = setTimeout(function () { bar.classList.remove("active"); }, isError ? 8000 : 5000);
  }

  function closeDialog() {
    var host = document.getElementById("dialog-host");
    if (!host) return;
    var dialog = host.querySelector("dialog");
    if (dialog && dialog.open) dialog.close();
    host.innerHTML = "";
  }

  document.addEventListener("DOMContentLoaded", function () {
    applyTheme(readTheme());
  });

  document.addEventListener("click", function (event) {
    if (event.target.closest("[data-theme-toggle]")) {
      toggleTheme();
    } else if (event.target.closest("[data-close-dialog]")) {
      closeDialog();
    }
  });

  // A dialog swapped into #dialog-host opens as a modal.
  document.addEventListener("htmx:afterSwap", function (event) {
    var target = event.detail.target;
    if (target && target.id === "dialog-host") {
      var dialog = target.querySelector("dialog");
      if (dialog && !dialog.open) {
        dialog.showModal();
        var first = dialog.querySelector("input:not([type=hidden]), select");
        if (first) first.focus();
      }
    }
  });

  // HX-Trigger events sent by the server.
  document.addEventListener("nekoNotify", function (event) {
    notify(event.detail.message, event.detail.error);
  });
  // Deferred: htmx dispatches the remaining HX-Trigger events on the form inside
  // the dialog; removing it now would detach them from the document.
  document.addEventListener("nekoClose", function () { setTimeout(closeDialog, 0); });

  document.addEventListener("htmx:responseError", function (event) {
    var xhr = event.detail.xhr;
    notify(xhr.status === 403 ? (xhr.responseText || "Not allowed") : "Request failed (" + xhr.status + ")", true);
  });
  document.addEventListener("htmx:sendError", function () {
    notify("The server cannot be reached", true);
  });
})();
