# Vendored front-end libraries

These files are compiled into the platform binary (`import()` in
`presentation/web/assets.d` and `presentation/web/icons.d`) and served under
`/ui/`. The platform runs in isolated security domains without CDN access, and
the UI Content-Security-Policy only allows the platform's own origin.

| File | Package | Source | License |
|---|---|---|---|
| `tabler.min.css` | @tabler/core 1.7.3 | `https://registry.npmjs.org/@tabler/core/-/core-1.7.3.tgz` → `dist/css/tabler.min.css` | MIT (`LICENSE.tabler`) |
| `tabler.min.js` | @tabler/core 1.7.3 (bundles Bootstrap 5 components as `window.tabler`) | same archive → `dist/js/tabler.min.js` | MIT (`LICENSE.tabler`) |
| `icons/*.svg` | @tabler/icons 3.50.0, outline set | `https://registry.npmjs.org/@tabler/icons/-/icons-3.50.0.tgz` → `icons/outline/` | MIT (`LICENSE.tabler-icons`) |
| `htmx.min.js` | htmx.org 2.0.11 | `https://cdn.jsdelivr.net/npm/htmx.org@2.0.11/dist/htmx.min.js` | 0BSD (`LICENSE.htmx`) |

Local changes:

- The `sourceMappingURL` comments were removed from `tabler.min.css` and
  `tabler.min.js`, because the maps are not shipped. The stylesheet only
  references `data:` URIs, so nothing outside the platform is loaded.
- Only the icons the pages use are copied. Each is minified onto one line: the
  invisible bounding-box path is dropped, and the class becomes
  `class="icon" aria-hidden="true" focusable="false"` (Tabler sizes `.icon`).

## Updating

1. Download the new archives (change the version numbers above) and copy the
   files again, then remove the `sourceMappingURL` comments.
2. Rename the published paths in `presentation/web/assets.d` and
   `views/head.dt` (`tabler-<version>.min.css|js`, `htmx-<version>.min.js`).
   They are cached for a year, so the name must change with the content.
3. To add an icon, copy `icons/outline/<name>.svg`, minify it as described
   above, and add `<name>` to the list in `presentation/web/icons.d`. Its
   unittest checks that every listed icon exists.
4. htmx 4.x changes attribute inheritance; check `views/*.dt` before moving off 2.x.
