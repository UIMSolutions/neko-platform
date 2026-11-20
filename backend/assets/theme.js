// Applies the saved light / dark choice before the page is painted (loaded
// without defer in <head>). Without a saved choice the OS setting decides.
(function () {
  "use strict";
  var mode = null;
  try { mode = localStorage.getItem("neko.theme"); } catch (e) { /* private mode */ }
  if (mode !== "light" && mode !== "dark")
    mode = window.matchMedia && window.matchMedia("(prefers-color-scheme: dark)").matches ? "dark" : "light";
  document.documentElement.setAttribute("data-bs-theme", mode);
})();
