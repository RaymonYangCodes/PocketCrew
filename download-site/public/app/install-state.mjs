export function bindInstallVisibility(button, win = window, nav = navigator) {
  const modes = ['standalone', 'minimal-ui', 'window-controls-overlay']
    .map(mode => win.matchMedia(`(display-mode: ${mode})`));
  let justInstalled = false;
  const update = () => {
    button.hidden = justInstalled || nav.standalone === true || modes.some(mode => mode.matches);
  };
  modes.forEach(mode => {
    if (mode.addEventListener) mode.addEventListener('change', update);
    else mode.addListener?.(update);
  });
  win.addEventListener('appinstalled', () => { justInstalled = true; update(); });
  win.addEventListener('pageshow', update);
  update();
}
