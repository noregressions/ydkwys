/* Injected into every generated page this server hands out.
 *
 * Read a page on its own and it grows one button: open the terminal beside
 * *this* page. Read the same page inside the split view and the button stays
 * away -- you are already there -- and the page instead tells the shell
 * around it where it is, so the shell's title, picker and URL follow along
 * as you navigate the site in the left pane.
 *
 * Nothing here is written to disk: serve.py injects the script tag on the
 * way out, so target/site stays exactly as `mvn package` left it.
 */

(function () {
  'use strict';

  var framed;
  try { framed = window.self !== window.top; } catch (e) { framed = true; }

  /* Where am I, as a /view?doc= value: the path minus its leading slash,
     hash included so a launch keeps your place in a long lesson. */
  function docParam() {
    return encodeURIComponent(location.pathname.replace(/^\/+/, '') + location.hash);
  }

  if (framed) {
    // Tell the shell where the left pane has got to. The shell also reads
    // this on iframe load; this covers in-page anchor clicks, which do not
    // reload anything.
    var announce = function () {
      try {
        parent.postMessage({
          type: 'ydkwys:nav',
          doc: location.pathname.replace(/^\/+/, ''),
          hash: location.hash,
          title: document.title
        }, location.origin);
      } catch (e) { /* not our parent; nothing to tell */ }
    };
    if (document.readyState === 'loading') {
      document.addEventListener('DOMContentLoaded', announce);
    } else {
      announce();
    }
    window.addEventListener('hashchange', announce);
    return;
  }

  /* Standalone: offer the way in. Fixed, bottom-right, out of the text. */
  function addButton() {
    if (document.getElementById('ydkwys-launch')) return;

    var link = document.createElement('a');
    link.id = 'ydkwys-launch';
    link.href = '/view?doc=' + docParam();
    link.textContent = '⬚  Open with terminal';
    link.title = 'Open this page beside a shell in the workshop container';
    link.setAttribute('aria-label', link.title);
    link.style.cssText = [
      'position:fixed', 'right:18px', 'bottom:18px', 'z-index:2147483000',
      'display:inline-flex', 'align-items:center', 'gap:8px',
      'padding:10px 16px', 'border-radius:999px',
      'background:#0d1117', 'color:#e6edf3', 'border:1px solid #4ea1ff',
      'box-shadow:0 4px 18px rgba(0,0,0,.38)',
      'font:600 13px/1 -apple-system,BlinkMacSystemFont,"Segoe UI",Roboto,sans-serif',
      'text-decoration:none', 'cursor:pointer'
    ].join(';');

    // Keep it off the printed book and out of the PDF path.
    var print = document.createElement('style');
    print.textContent = '@media print { #ydkwys-launch { display: none !important; } }';

    document.head.appendChild(print);
    document.body.appendChild(link);
  }

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', addButton);
  } else {
    addButton();
  }
})();

/* Copy buttons for /md/** pages only.
 *
 * The generated pages bring paperband's own copy buttons, so this binds
 * strictly to `.block button.copy`, which is markup only serve.py's Markdown
 * renderer produces. On a generated page the selector matches nothing.
 */
(function () {
  'use strict';

  async function toClipboard(text) {
    try {
      if (navigator.clipboard && window.isSecureContext) {
        await navigator.clipboard.writeText(text);
        return true;
      }
    } catch (e) { /* fall through to the legacy path */ }
    // A LAN address over http is not a secure context, and a workshop is
    // exactly where someone opens this from the next machine along.
    var ta = document.createElement('textarea');
    ta.value = text;
    ta.setAttribute('readonly', '');
    ta.style.cssText = 'position:fixed;top:-1000px;opacity:0';
    document.body.appendChild(ta);
    ta.select();
    var ok = false;
    try { ok = document.execCommand('copy'); } catch (e) { ok = false; }
    ta.remove();
    return ok;
  }

  document.addEventListener('click', async function (ev) {
    var button = ev.target.closest && ev.target.closest('.block button.copy');
    if (!button) return;
    var code = button.closest('.block').querySelector('code');
    if (!code) return;

    var ok = await toClipboard(code.textContent.replace(/\s+$/, ''));
    button.textContent = ok ? 'Copied' : 'Press ⌘C';
    button.classList.toggle('done', ok);
    if (!ok) {                       // last resort: leave it selected to copy
      var range = document.createRange();
      range.selectNodeContents(code);
      getSelection().removeAllRanges();
      getSelection().addRange(range);
    }
    setTimeout(function () {
      button.textContent = 'Copy';
      button.classList.remove('done');
    }, 1400);
  });
})();
