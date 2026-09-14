(() => {
  const options = window.__rtideOutputOptions || {};
  const old = document.getElementById('rtide-output-nav');
  if (old && old.dataset.version === '2') { old.refresh(); return true; }
  old?.remove();
  const marker = '/.tweb/';
  const cut = location.href.indexOf(marker);
  const workspace = cut >= 0 ? location.href.slice(0, cut) : location.origin;
  const key = 'rtide-output-zoom:' + workspace;
  let preference = 'auto';
  try { preference = localStorage.getItem(key) || 'auto'; } catch (_) {}
  const clamp = value => Math.max(0.5, Math.min(3, value));
  if (preference !== 'auto' && !(Number(preference) >= 0.5 && Number(preference) <= 3)) preference = 'auto';
  // Match 16px body text to roughly 65% of a terminal line. The browser
  // viewport is already expressed in CSS pixels at TWeb's native zoom.
  // Retain this physical reading size when the window changes dimensions.
  const rows = Number(options.rows);
  const autoZoom = Number(options.zoom) > 0 ? clamp(Number(options.zoom)) :
    Math.max(1, Math.min(1.75, Math.round((rows > 0 ? innerHeight / rows * 0.65 / 16 : 1.25) * 20) / 20));
  const host = document.createElement('div');
  host.id = 'rtide-output-nav';
  host.dataset.version = '2';
  const shadow = host.attachShadow({mode: 'open'});
  shadow.innerHTML = `<style>
    *{box-sizing:border-box}.bar{display:flex;align-items:center;gap:2px;padding:4px;border:1px solid #ffffff30;border-radius:10px;background:#101923;color:#eef5fa;box-shadow:0 4px 18px #0005;font:600 14px/1 system-ui}
    button,a{display:grid;place-items:center;min-width:32px;height:34px;padding:0 8px;border:0;border-radius:6px;background:transparent;color:inherit;font:inherit;cursor:pointer;text-decoration:none;white-space:nowrap}
    button:hover,a:hover{background:#ffffff18}button:focus-visible,a:focus-visible{outline:2px solid #81dbc0;outline-offset:1px}button:disabled{opacity:.35;cursor:default}.sep{border-left:1px solid #ffffff30;height:20px;margin:0 3px}#auto[aria-pressed=true]{color:#81dbc0}#value{min-width:48px;text-align:center;font-variant-numeric:tabular-nums}.history{color:#81dbc0}
    @media(max-width:440px){.history{display:none}.bar{gap:0}button,a{padding:0 5px}}
    </style><nav class="bar" aria-label="Output navigation and zoom">
    <button id="back" aria-label="Previous page" title="Previous page">←</button><a class="history">Outputs</a><button id="forward" aria-label="Next page" title="Next page">→</button><span class="sep"></span>
    <button id="minus" aria-label="Zoom out" title="Zoom out">−</button><output id="value" aria-live="polite"></output><button id="plus" aria-label="Zoom in" title="Zoom in">+</button><button id="auto" title="Match terminal text size" aria-label="Automatic readable zoom">Auto</button></nav>`;
  const get = id => shadow.getElementById(id);
  const outputs = cut >= 0 ? new URL(location.href.slice(0,cut+marker.length) + 'history.html').href : new URL('history.html', location.href).href;
  shadow.querySelector('a').href = outputs;
  get('back').onclick = () => history.back();
  get('forward').onclick = () => history.forward();
  let current;
  const apply = () => {
    current = preference === 'auto' ? autoZoom : clamp(Number(preference));
    document.documentElement.style.zoom = String(current);
    // Counter-scale the controls so increasing page zoom cannot hide them.
    host.style.cssText = `position:fixed;z-index:2147483647;top:10px;right:10px;zoom:${1 / current}`;
    get('value').textContent = Math.round(current * 100) + '%';
    get('auto').setAttribute('aria-pressed', String(preference === 'auto'));
    get('minus').disabled = current <= 0.5;
    get('plus').disabled = current >= 3;
  };
  const choose = value => {
    preference = value;
    try { localStorage.setItem(key, String(value)); } catch (_) {}
    apply();
  };
  get('minus').onclick = () => choose(clamp(Math.round((current - 0.1) * 100) / 100));
  get('plus').onclick = () => choose(clamp(Math.round((current + 0.1) * 100) / 100));
  get('auto').onclick = () => choose('auto');
  host.refresh = apply;
  document.body.appendChild(host);
  apply();
  return true;
})()
