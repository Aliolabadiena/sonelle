# Vendored third-party assets

These files are bundled verbatim so the app works offline. All are MIT-licensed.

- `xterm.js`, `xterm.css` - [@xterm/xterm](https://github.com/xtermjs/xterm.js) v5.5.0
  (UMD build -> `window.Terminal`). Copyright (c) 2017-2024 The xterm.js authors. MIT.
- `addon-fit.js` - [@xterm/addon-fit](https://github.com/xtermjs/xterm.js) v0.10.0
  (UMD build -> `window.FitAddon.FitAddon`). MIT.
- `addon-webgl.js` - [@xterm/addon-webgl](https://github.com/xtermjs/xterm.js) v0.18.0
  (UMD build -> `window.WebglAddon.WebglAddon`). The GPU renderer - no flicker/ghosting over the
  glass background. MIT.

To refresh (versions must stay paired - 5.5.0 core <-> 0.10.0 fit <-> 0.18.0 webgl):

    curl -fsSL https://cdn.jsdelivr.net/npm/@xterm/xterm@5.5.0/lib/xterm.js          -o xterm.js
    curl -fsSL https://cdn.jsdelivr.net/npm/@xterm/xterm@5.5.0/css/xterm.css         -o xterm.css
    curl -fsSL https://cdn.jsdelivr.net/npm/@xterm/addon-fit@0.10.0/lib/addon-fit.js   -o addon-fit.js
    curl -fsSL https://cdn.jsdelivr.net/npm/@xterm/addon-webgl@0.18.0/lib/addon-webgl.js -o addon-webgl.js
