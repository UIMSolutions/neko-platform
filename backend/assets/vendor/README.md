# Vendored front-end libraries

These files are compiled into the platform binary (`import()` in
`presentation/web/assets.d`) and served under `/ui/`. The platform runs in
isolated security domains without CDN access, and the UI Content-Security-Policy
only allows the platform's own origin.

| File | Package | Source | License |
|---|---|---|---|
| `beer.min.css` | beercss 5.0.3 | `https://cdn.jsdelivr.net/npm/beercss@5.0.3/dist/cdn/beer.min.css` | MIT (`LICENSE.beercss`) |
| `material-symbols-outlined.woff2` | beercss 5.0.3 (Google Material Symbols) | `…/beercss@5.0.3/dist/cdn/material-symbols-outlined.woff2` | Apache-2.0 |
| `material-symbols-subset.woff2` | beercss 5.0.3 | `…/beercss@5.0.3/dist/cdn/material-symbols-subset.woff2` | Apache-2.0 |
| `htmx.min.js` | htmx.org 2.0.11 | `https://cdn.jsdelivr.net/npm/htmx.org@2.0.11/dist/htmx.min.js` | 0BSD (`LICENSE.htmx`) |

Local change: in `beer.min.css` the CDN fallback URLs of the four icon fonts
(`url(https://cdn.jsdelivr.net/…woff2)`) were removed, so the stylesheet
references nothing outside the platform. The local `url(material-symbols-*.woff2)`
entries are unchanged.

`beer.min.js` is not used: native `<dialog>`, CSS-only floating labels
(`placeholder=" "`) and `../app.js` cover what the pages need, and its runtime
loader would fetch further files.

## Updating

1. Download the new versions from the URLs above (change the version numbers).
2. Strip the CDN font fallbacks from `beer.min.css` again.
3. Rename the published paths in `presentation/web/assets.d` and
   `views/head.dt` (`beer-<version>.min.css`, `htmx-<version>.min.js`). They are
   cached for a year, so the name must change with the content.
4. htmx 4.x changes attribute inheritance; check `views/*.dt` before moving off 2.x.
