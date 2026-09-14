(() => {
  const options = window.__rtideOutputOptions || {};
  const old = document.getElementById('rtide-output-nav');
  if (window.__rtideExporting) return '{}';
  if (old && old.dataset.version === '3') { old.refresh(options); return JSON.stringify(old.state()); }
  old?.remove();
  const marker = '/.tweb/';
  const cut = location.href.indexOf(marker);
  const workspace = options.workspace || (cut >= 0 ? location.href.slice(0, cut) : location.origin);
  const key = 'rtide-output-zoom:' + workspace;
  let preference = 'auto';
  let updated = 0;
  try {
    const stored = localStorage.getItem(key);
    if (stored?.startsWith('{')) {
      const saved = JSON.parse(stored); preference = saved.preference; updated = saved.updated || 0;
    } else preference = stored || 'auto';
  } catch (_) {}
  if (options.preference !== undefined && (options.updated || 0) >= updated) {
    preference = options.preference; updated = options.updated || 0;
  }
  const clamp = value => Math.max(0.5, Math.min(3, value));
  if (preference !== 'auto' && !(Number(preference) >= 0.5 && Number(preference) <= 3)) preference = 'auto';
  // Match 16px body text to roughly 65% of a terminal line. The browser
  // viewport is already expressed in CSS pixels at TWeb's native zoom.
  // Retain this physical reading size when the window changes dimensions.
  let autoZoom;
  const measure = settings => {
    const rows = Number(settings.rows);
    autoZoom = Number(settings.zoom) > 0 ? clamp(Number(settings.zoom)) :
      Math.max(1, Math.min(1.75, Math.round((rows > 0 ? innerHeight / rows * 0.65 / 16 : 1.25) * 20) / 20));
  };
  measure(options);
  const viewer = location.pathname.endsWith('/.tweb/viewer.html') ? document.getElementById('artifact') : null;
  const nativeNav = viewer ? document.querySelector('body > nav') : null;
  const baseFont = parseFloat(getComputedStyle(document.body).fontSize) || 16;
  const basePadding = parseFloat(getComputedStyle(document.body).paddingTop) || 0;
  const host = document.createElement('div');
  host.id = 'rtide-output-nav';
  host.dataset.version = '3';
  const shadow = host.attachShadow({mode: 'open'});
  shadow.innerHTML = `<style>
    *{box-sizing:border-box}.bar{display:flex;align-items:center;gap:2px;padding:4px;border:1px solid #ffffff30;border-radius:10px;background:#101923;color:#eef5fa;box-shadow:0 4px 18px #0005;font:600 14px/1 system-ui}
    button,a{display:grid;place-items:center;min-width:32px;height:34px;padding:0 8px;border:0;border-radius:6px;background:transparent;color:inherit;font:inherit;cursor:pointer;text-decoration:none;white-space:nowrap}
    button:hover,a:hover{background:#ffffff18}button:focus-visible,a:focus-visible{outline:2px solid #81dbc0;outline-offset:1px}button:disabled{opacity:.35;cursor:default}.sep{border-left:1px solid #ffffff30;height:20px;margin:0 3px}#auto[aria-pressed=true]{color:#81dbc0}#value{min-width:48px;text-align:center;font-variant-numeric:tabular-nums}.history{color:#81dbc0}
    @media(max-width:440px){.history{display:none}.bar{gap:0}button,a{padding:0 5px}}
    @media print{.bar{display:none!important}}
    </style><nav class="bar" aria-label="Output navigation and zoom">
    <button id="back" aria-label="Previous page" title="Previous page">←</button><a class="history">Outputs</a><button id="forward" aria-label="Next page" title="Next page">→</button><span class="sep"></span>
    <button id="minus" aria-label="Zoom out" title="Zoom out">−</button><output id="value" aria-live="polite"></output><button id="plus" aria-label="Zoom in" title="Zoom in">+</button><button id="auto" title="Match terminal text size" aria-label="Automatic readable zoom">Auto</button></nav>`;
  const get = id => shadow.getElementById(id);
  const outputs = options.workspace ? options.workspace + '/.tweb/history.html' : (cut >= 0 ? new URL(location.href.slice(0,cut+marker.length) + 'history.html').href : new URL('history.html', location.href).href);
  shadow.querySelector('a').href = outputs;
  get('back').onclick = () => history.back();
  get('forward').onclick = () => history.forward();
  let current;
  const apply = () => {
    current = preference === 'auto' ? autoZoom : clamp(Number(preference));
    const zoom = current * 16 / baseFont;
    if (viewer && nativeNav) {
      document.documentElement.style.zoom = '1';
      host.style.cssText = 'margin-left:auto;flex-shrink:0';
      try {
        const child = viewer.contentDocument;
        if (!child?.body) throw Error('Frame not accessible');
        const childFont = parseFloat(getComputedStyle(child.body).fontSize) || 16;
        child.documentElement.style.zoom = String(current * 16 / childFont);
        child.getElementById('rtide-output-nav')?.remove();
        if (/\/results\/result-[^/]+\.html$/.test(child.location.pathname)) child.querySelector('.topnav')?.remove();
        viewer.style.zoom = '1'; viewer.style.width = '100%'; viewer.style.height = '100%';
      } catch (_) {
        // Cross-origin documents remain in their own origin; scale the frame.
        viewer.style.zoom = String(current);
        viewer.style.width = `${100 / current}%`;
        viewer.style.height = `${100 / current}%`;
      }
    } else {
      document.documentElement.style.zoom = String(zoom);
      document.body.style.paddingTop = `${basePadding + 58 / zoom}px`;
      // Keep one consistent control size independent of content typography.
      host.style.cssText = `position:fixed;z-index:2147483647;top:8px;right:8px;zoom:${1 / zoom}`;
    }
    get('value').textContent = Math.round(current * 100) + '%';
    get('auto').setAttribute('aria-pressed', String(preference === 'auto'));
    get('minus').disabled = current <= 0.5;
    get('plus').disabled = current >= 3;
  };
  const choose = value => {
    preference = value;
    updated = Date.now();
    try { localStorage.setItem(key, JSON.stringify({preference: value, updated})); } catch (_) {}
    apply();
  };
  get('minus').onclick = () => choose(clamp(Math.round((current - 0.1) * 100) / 100));
  get('plus').onclick = () => choose(clamp(Math.round((current + 0.1) * 100) / 100));
  get('auto').onclick = () => choose('auto');
  host.refresh = settings => { measure(settings); apply(); };
  host.state = () => ({preference: preference === 'auto' ? 'auto' : Number(preference), updated});
  if (viewer && nativeNav) {
    get('back').remove(); get('forward').remove();
    shadow.querySelector('a').remove(); shadow.querySelector('.sep').remove();
    nativeNav.style.overflowX = 'auto';
    nativeNav.appendChild(host);
    viewer.addEventListener('load', apply);
  } else document.body.appendChild(host);
  if (/\/(results\/result-[^/]+|history[^/]*|agent)\.html$/.test(location.pathname)) {
    document.querySelector('.topnav')?.remove();
  }
  apply();
  return JSON.stringify(host.state());
})()
