/* The split view.
 *
 * The left pane is an iframe of a real page from the generated site, so the
 * book's own styling, anchors and copy buttons all work as written and no
 * markup is rewritten. Everything here is same-origin, which is what makes
 * the two useful tricks possible: reading the framed page's headings to
 * build a jump list, and following its navigation in this bar.
 *
 * The right pane is ttyd, and it is never reloaded by a left-pane
 * navigation -- that is the reason the page is framed rather than given a
 * terminal of its own. Your shell, its history and any running server
 * survive moving from S01 to S04.
 */

'use strict';

const $ = (id) => document.getElementById(id);
const STORE = 'ydkwys-view';

const state = { docs: [], config: {}, doc: null };

const prefs = (() => {
  try { return JSON.parse(localStorage.getItem(STORE)) || {}; } catch { return {}; }
})();

function savePrefs(patch) {
  Object.assign(prefs, patch);
  try { localStorage.setItem(STORE, JSON.stringify(prefs)); } catch { /* private window */ }
}

function flash(msg, ms = 1800) {
  const el = $('status');
  el.textContent = msg;
  clearTimeout(flash.timer);
  flash.timer = setTimeout(() => { el.textContent = ''; }, ms);
}

/* --- the instructions pane ----------------------------------------------- */

function show(doc) {
  if (!doc) return;
  $('page').src = '/' + doc.replace(/^\/+/, '');
  mark(doc);
}

/* Record where the pane is: state, prefs, address bar and picker together.
   Called from three places -- an explicit pick, an iframe load, and
   launcher.js reporting an in-page anchor move -- so it has to be
   idempotent rather than conditional on having changed. An earlier version
   guarded the picker update on `doc !== state.doc`, and the postMessage
   (which arrives before the load event) made that guard skip it. */
function mark(doc) {
  state.doc = doc;
  savePrefs({ doc });
  syncUrl(doc);
  const bare = doc.split('#')[0];
  const known = state.docs.find((d) => d.path === bare);
  $('doc').value = known ? known.path : '';
}

/* Keep the address bar on the page you are actually reading, so the view is
   linkable: send someone /view?doc=site/cards/s04-... and they land on that
   lesson with a terminal already beside it. */
function syncUrl(doc) {
  const url = `${location.pathname === '/' ? '/view' : location.pathname}?doc=${encodeURIComponent(doc)}`;
  history.replaceState(null, '', url);
  $('pop').href = '/' + doc.replace(/^\/+/, '');
}

/* Build the jump list from the framed page itself. The generated pages put
   ids on their sidebar sections but not on content headings, so give the
   headings ids here -- harmless, same-origin, and it makes every lesson
   navigable without touching the build. */
function buildToc() {
  const toc = $('toc');
  toc.innerHTML = '<option value="">Jump to…</option>';

  let doc;
  try { doc = $('page').contentDocument; } catch { doc = null; }
  if (!doc) { toc.disabled = true; return; }

  const headings = [...doc.querySelectorAll('h1, h2, h3, h4')].filter((h) => {
    if (h.closest('#paperband-sidebar, nav, aside')) return false;   // site nav
    return h.textContent.trim().length > 0;
  });

  let n = 0;
  for (const h of headings) {
    if (!h.id) h.id = 'view-h' + (++n);
    const level = Number(h.tagName[1]);
    const option = document.createElement('option');
    option.value = h.id;
    option.textContent = '   '.repeat(Math.max(0, level - 1)) + h.textContent.trim().slice(0, 90);
    toc.appendChild(option);
  }
  toc.disabled = headings.length === 0;
}

$('page').addEventListener('load', () => {
  // Follow the reader if they navigated inside the pane -- every generated
  // page carries the whole site nav, so this is the normal way around.
  let framed = null;
  try { framed = $('page').contentWindow.location.pathname.replace(/^\/+/, ''); } catch { /* ignore */ }
  if (framed) mark(framed);
  buildToc();
  try { document.title = $('page').contentDocument.title + ' — with terminal'; } catch { /* ignore */ }
});

/* launcher.js in the framed page reports in-page anchor moves, which fire no
   load event. */
window.addEventListener('message', (ev) => {
  if (ev.origin !== location.origin || !ev.data || ev.data.type !== 'ydkwys:nav') return;
  mark(ev.data.doc + (ev.data.hash || ''));
});

$('doc').addEventListener('change', (ev) => show(ev.target.value));

$('toc').addEventListener('change', (ev) => {
  const id = ev.target.value;
  ev.target.selectedIndex = 0;
  if (!id) return;
  try {
    const target = $('page').contentDocument.getElementById(id);
    if (target) target.scrollIntoView({ behavior: 'smooth', block: 'start' });
  } catch { flash('cannot scroll that page'); }
});

function buildPicker() {
  const picker = $('doc');
  picker.innerHTML = '';
  let group = null;
  for (const doc of state.docs) {
    if (doc.group !== group) {
      group = doc.group;
      picker.appendChild(Object.assign(document.createElement('optgroup'), { label: group }));
    }
    const option = document.createElement('option');
    option.value = doc.path;
    option.textContent = doc.title;
    picker.lastElementChild.appendChild(option);
  }
}

/* --- the terminal pane --------------------------------------------------- */

function connectTerminal() {
  const port = state.config.ttydPort || 7681;
  // location.hostname, not localhost: this has to work when the page is
  // opened from another machine on the workshop network.
  $('tty').src = `${location.protocol}//${location.hostname}:${port}/`;
}

$('reconnect').addEventListener('click', () => {
  connectTerminal();
  flash('shell reloaded');
});

/* --- splitter ------------------------------------------------------------ */

(() => {
  const drag = $('drag');
  const pane = $('pane');
  if (prefs.width) pane.style.width = prefs.width;

  let active = false;

  drag.addEventListener('mousedown', (ev) => {
    active = true;
    ev.preventDefault();
    document.body.classList.add('dragging');
    drag.classList.add('active');
  });

  window.addEventListener('mousemove', (ev) => {
    if (!active) return;
    const pct = (ev.clientX / window.innerWidth) * 100;
    pane.style.width = `${Math.min(78, Math.max(22, pct))}%`;
  });

  window.addEventListener('mouseup', () => {
    if (!active) return;
    active = false;
    document.body.classList.remove('dragging');
    drag.classList.remove('active');
    savePrefs({ width: pane.style.width });
  });

  drag.addEventListener('dblclick', () => {
    pane.style.width = '52%';
    savePrefs({ width: '52%' });
  });
})();

/* --- boot ---------------------------------------------------------------- */

(async () => {
  try {
    const [config, docs] = await Promise.all([
      fetch('/api/config').then((r) => r.json()),
      fetch('/api/docs').then((r) => r.json()),
    ]);
    state.config = config;
    state.docs = docs.docs;
  } catch {
    flash('the instructions server is not responding', 8000);
    return;
  }

  buildPicker();
  connectTerminal();

  // What to show, most specific first: an explicit ?doc=, then wherever you
  // were last time, then the first page in the picker.
  const asked = new URLSearchParams(location.search).get('doc');
  const remembered = prefs.doc;
  const first = state.docs[0] && state.docs[0].path;
  show(asked || remembered || first);

  if (state.config.source === 'markdown') {
    flash('book not built — showing Markdown sources', 6000);
  }
})();
