/* sonelle colour palettes - 20 curated themes for the settings panel.
   Each entry is a COMPACT seed (bg / bg2 / accent / pink / txt); app.js applyPalette() derives the
   rest of the CSS custom properties (--dim/--faint/--hair/--accent-soft/--moody...) and the xterm
   THEME from these, then writes them onto :root and re-themes every live terminal. Keep them
   eye-easy / on-brand. Loaded before app.js; exposed as window.SONELLE_PALETTES. */
(function () {
  "use strict";
  window.SONELLE_PALETTES = [
    { id: "indigo",   name: "Indigo",   bg: "#080a18", bg2: "#141a3a", accent: "#8b96e6", pink: "#ff79c6", txt: "#d3d6ec" },
    { id: "midnight", name: "Midnight", bg: "#06070f", bg2: "#10162e", accent: "#6f7bd6", pink: "#e879c6", txt: "#cdd2ea" },
    { id: "royal",    name: "Royal",    bg: "#07091f", bg2: "#101040", accent: "#6060d0", pink: "#c4b8ee", txt: "#d3d6ec" },
    { id: "violet",   name: "Violet",   bg: "#0f0a18", bg2: "#20143a", accent: "#a07fe0", pink: "#ff79c6", txt: "#ddd6ec" },
    { id: "plum",     name: "Plum",     bg: "#110a16", bg2: "#281432", accent: "#b87fd0", pink: "#ff8ad3", txt: "#e6d6ec" },
    { id: "rose",     name: "Rose",     bg: "#160a10", bg2: "#321428", accent: "#e07fb0", pink: "#ff79c6", txt: "#ecd6e6" },
    { id: "crimson",  name: "Crimson",  bg: "#14080a", bg2: "#2e1218", accent: "#d96a7a", pink: "#ff8aa0", txt: "#ecd0d6" },
    { id: "sunset",   name: "Sunset",   bg: "#160c0a", bg2: "#321a14", accent: "#e0875f", pink: "#ff79a0", txt: "#ecd6cf" },
    { id: "amber",    name: "Amber",    bg: "#14100a", bg2: "#2e2412", accent: "#dcb066", pink: "#ff9b85", txt: "#ece0cf" },
    { id: "gold",     name: "Gold",     bg: "#100e08", bg2: "#2a2410", accent: "#c9a84f", pink: "#e0a080", txt: "#e6dcc6" },
    { id: "forest",   name: "Forest",   bg: "#0a1109", bg2: "#1a2a16", accent: "#7faa55", pink: "#e0a0c0", txt: "#dde6cf" },
    { id: "emerald",  name: "Emerald",  bg: "#06120c", bg2: "#11301f", accent: "#5fc08a", pink: "#ff9bd3", txt: "#d2ead9" },
    { id: "mint",     name: "Mint",     bg: "#08120e", bg2: "#102a22", accent: "#6fc0a0", pink: "#ff9bd3", txt: "#d2ece0" },
    { id: "teal",     name: "Teal",     bg: "#05110f", bg2: "#0e2a28", accent: "#4fb3a3", pink: "#ff9bb0", txt: "#cfe7e2" },
    { id: "ocean",    name: "Ocean",    bg: "#050d18", bg2: "#0e2240", accent: "#4f8fd0", pink: "#9bb8ff", txt: "#cfe0ec" },
    { id: "sky",      name: "Sky",      bg: "#081016", bg2: "#142a3a", accent: "#6fb0e0", pink: "#ff9bd3", txt: "#d2e4ec" },
    { id: "ice",      name: "Ice",      bg: "#0a0f14", bg2: "#182530", accent: "#8fbcd4", pink: "#d8a0c0", txt: "#d6e2ea" },
    { id: "slate",    name: "Slate",    bg: "#0b0e16", bg2: "#1a2030", accent: "#7d8aa6", pink: "#d98aa0", txt: "#d2d7e2" },
    { id: "graphite", name: "Graphite", bg: "#0a0a0c", bg2: "#1c1c22", accent: "#8088a0", pink: "#b890a8", txt: "#d2d4dc" },
    { id: "mono",     name: "Mono",     bg: "#0c0c0e", bg2: "#20202a", accent: "#9a9ab0", pink: "#c0a0b0", txt: "#d6d6de" }
  ];
})();
