// Neko Platform pages: dialogs, toasts and theme switch for Tabler + htmx.
// Loaded as a file because the Content-Security-Policy forbids inline scripts.
// Tabler (window.tabler) bundles the Bootstrap components used here.
(function () {
  "use strict";

  var THEME_KEY = "neko.theme";

  function setTheme(mode) {
    try { localStorage.setItem(THEME_KEY, mode); } catch (e) { /* private mode */ }
    document.documentElement.setAttribute("data-bs-theme", mode);
  }

  // ── toasts ──────────────────────────────────────────────────────────────
  function notify(message, isError) {
    var el = document.getElementById("toast");
    if (!el || !message) return;
    el.querySelector(".toast-body").textContent = message;
    el.classList.toggle("text-bg-danger", !!isError);
    el.classList.toggle("text-bg-success", !isError);
    window.tabler.Toast.getOrCreateInstance(el, { delay: isError ? 8000 : 5000 }).show();
  }

  // ── dialogs (Tabler modals loaded into #dialog-host) ─────────────────────
  function currentModal() {
    return document.querySelector("#dialog-host > .modal");
  }

  function openModal() {
    var el = currentModal();
    if (!el || el.dataset.opened) return;
    el.dataset.opened = "1";
    el.addEventListener("hidden.bs.modal", function () { el.remove(); });
    el.addEventListener("shown.bs.modal", function () { focusFirst(el); });
    window.tabler.Modal.getOrCreateInstance(el).show();
  }

  function focusFirst(el) {
    var first = el.querySelector(".modal-body input:not([type=hidden]):not([disabled]), .modal-body select");
    if (first) first.focus();
  }

  function closeModal() {
    var el = currentModal();
    if (!el) return;
    var modal = window.tabler.Modal.getInstance(el);
    if (modal) modal.hide(); else el.remove();
  }

  document.addEventListener("click", function (event) {
    var toggle = event.target.closest("[data-theme-toggle]");
    if (toggle) setTheme(toggle.getAttribute("data-theme-toggle"));
  });

  document.addEventListener("htmx:afterSettle", function (event) {
    openModal();
    // a dialog re-rendered with a validation error: focus its first field again
    var target = event.detail.elt;
    if (target && target.classList && target.classList.contains("modal-content")) focusFirst(target);
  });

  // HX-Trigger events sent by the server.
  document.addEventListener("nekoNotify", function (event) {
    notify(event.detail.message, event.detail.error);
  });
  // Deferred: htmx dispatches the remaining HX-Trigger events on the form inside
  // the dialog; removing it now would detach them from the document.
  document.addEventListener("nekoClose", function () { setTimeout(closeModal, 0); });

  document.addEventListener("htmx:responseError", function (event) {
    var xhr = event.detail.xhr;
    var text = xhr.getResponseHeader("Content-Type") || "";
    notify(text.indexOf("text/plain") === 0 && xhr.responseText ? xhr.responseText
      : "Request failed (" + xhr.status + ")", true);
  });
  document.addEventListener("htmx:sendError", function () {
    notify("The server cannot be reached", true);
  });
})();
