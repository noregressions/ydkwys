#!/usr/bin/env python3
"""The instructions half of the browser workshop view.

Serves three things on one port:

    /view?doc=<path>   the split view: a named page on the left, a terminal
                       on the right. The terminal is an iframe of ttyd, and
                       it survives every navigation in the left pane, which
                       is the whole point of framing the page rather than
                       bolting a terminal onto each one.
    /site/**           the generated book site (target/site), served as-is
    /cheatsheets/**    the generated cheatsheet site (target/cheatsheets-site)
    /md/<file>.md      a Markdown source rendered directly, for when the
                       book has not been built (see render_markdown)

Every generated page served from here gets one <script> injected into it:
launcher.js, which puts an "Open with terminal" button on the page when it is
read on its own, and stays out of the way when it is already in the view.
That is what makes the generated HTML the way in -- browse the site normally,
find the lesson you want, launch the terminal beside the page you are on.

Standard library only, on purpose: the workshop image has no Python packages
beyond pip-audit's and GuardDog's pipx environments, and a workshop is
exactly where you do not want a page that must reach a CDN to render.
"""

from __future__ import annotations

import html as html_mod
import json
import mimetypes
import os
import re
import sys
import urllib.parse
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

WEB_DIR = Path(__file__).resolve().parent
ROOT = WEB_DIR.parent.parent          # container/web/serve.py -> repository root

WEB_PORT = int(os.environ.get("WEB_PORT", "7680"))
TTYD_PORT = int(os.environ.get("TTYD_PORT", "7681"))

# The generated sites, in the order the picker offers them. Mounted under a
# URL prefix each, so relative links and assets inside them keep working.
SITES = {
    "site": ROOT / "target" / "site",
    "cheatsheets": ROOT / "target" / "cheatsheets-site",
}

# Where a generated page belongs in the picker. First match wins; anything
# unmatched still gets served, it just is not offered in the list.
GROUPS = (
    ("Cheat sheets",      r"^cheatsheets/cards/cheatsheet-.*\.html$"),
    ("Cheat sheets",      r"^cheatsheets/cheat-sheets\.html$"),
    ("Scenarios",         r"^site/cards/s\d+-.*\.html$"),
    ("Investigations",    r"^site/cards/t\d+-.*\.html$"),
    ("Book parts",        r"^site/(index|part-.*|introduction-.*|appendix-.*)\.html$"),
    ("CVE propagation",   r"^site/cards/cve-propagation-.*\.html$"),
    ("Workshop notes",    r"^site/cards/workshop-.*\.html$"),
    ("Setup & reference", r"^site/cards/(setup-.*|reference-.*|front)\.html$"),
)
GROUP_ORDER = ["Cheat sheets", "Scenarios", "Investigations", "Book parts",
               "CVE propagation", "Workshop notes", "Setup & reference"]

# Markdown sources, used when the book has not been built.
MD_SETS = (
    ("Cheatsheets (source)",    ["cheatsheet/*.md"]),
    ("Scenarios (source)",      ["scenarios/*/LESSON.md"]),
    ("Investigations (source)", ["investigations/*/LESSON.md"]),
    ("Workshop notes (source)", ["workshop/*.md", "workshop/cve-propagation/*.md"]),
    ("Setup (source)",          ["setup/*.md", "reference/*.md"]),
)

NO_COPY_LANGS = {"output", "mermaid"}
TITLE_TAIL = re.compile(r"\s+—\s+You Don't Know What You're Shipping.*$")


# --- shared helpers ----------------------------------------------------------

def repo_url() -> str:
    """The book's repoUrl var, read from pom.xml's <scm><url> like the build."""
    try:
        pom = (ROOT / "pom.xml").read_text(encoding="utf-8")
        m = re.search(r"<scm>.*?<url>\s*(.*?)\s*</url>", pom, re.S)
        if m:
            return m.group(1)
    except OSError:
        pass
    return "https://github.com/noregressions/ydkwys"


def safe_join(root: Path, rel: str) -> Path | None:
    """Resolve rel under root, or None if it escapes -- no traversal, ever."""
    root = root.resolve()
    try:
        target = (root / rel.lstrip("/")).resolve()
    except OSError:
        return None
    return target if target == root or root in target.parents else None


def sites_built() -> bool:
    return (SITES["site"] / "index.html").is_file()


# --- the picker --------------------------------------------------------------

_title_cache: dict[tuple[str, float], str] = {}


def page_title(path: Path) -> str:
    """A generated page's <title>, minus the book name every one of them carries."""
    try:
        key = (str(path), path.stat().st_mtime)
    except OSError:
        return path.stem
    if key in _title_cache:
        return _title_cache[key]
    title = path.stem
    try:
        # The title is in the first couple of KB; no need to read 130KB of card.
        with path.open("r", encoding="utf-8", errors="replace") as fh:
            head = fh.read(4096)
        m = re.search(r"<title>(.*?)</title>", head, re.S)
        if m:
            title = TITLE_TAIL.sub("", html_mod.unescape(m.group(1)).strip()) or path.stem
    except OSError:
        pass
    _title_cache[key] = title
    return title


def generated_docs() -> list[dict]:
    """Every generated page worth offering, grouped and ordered for the picker."""
    found: dict[str, list[dict]] = {}
    for prefix, base in SITES.items():
        if not base.is_dir():
            continue
        for path in sorted(base.rglob("*.html")):
            rel = f"{prefix}/{path.relative_to(base).as_posix()}"
            group = next((g for g, pattern in GROUPS if re.match(pattern, rel)), None)
            if group is None:
                continue
            found.setdefault(group, []).append(
                {"group": group, "path": rel, "title": page_title(path)})
    docs: list[dict] = []
    for group in GROUP_ORDER:
        docs.extend(sorted(found.get(group, []), key=lambda d: d["path"]))
    return docs


def markdown_docs() -> list[dict]:
    """The Markdown fallback list, used when target/site is not there."""
    docs, seen = [], set()
    for group, patterns in MD_SETS:
        for pattern in patterns:
            for path in sorted(ROOT.glob(pattern)):
                rel = path.relative_to(ROOT).as_posix()
                if rel in seen or "node_modules" in rel:
                    continue
                seen.add(rel)
                try:
                    text = path.read_text(encoding="utf-8")
                except OSError:
                    continue
                _, body = front_matter(text)
                title = title_of(body, path)
                if path.name in ("LESSON.md", "README.md"):
                    title = f"{path.parent.name} — {title}"
                docs.append({"group": group, "path": f"md/{rel}", "title": title})
    return docs


def picker_docs() -> tuple[list[dict], str]:
    if sites_built():
        return generated_docs(), "generated"
    return markdown_docs(), "markdown"


# --- markdown ----------------------------------------------------------------

FENCE = re.compile(r"^```([A-Za-z0-9+_-]*)\s*$")
HEADING = re.compile(r"^(#{1,6})\s+(.*)$")
BULLET = re.compile(r"^(\s*)[-*+]\s+(.*)$")
NUMBER = re.compile(r"^(\s*)\d+[.)]\s+(.*)$")
TABLE_RULE = re.compile(r"^\s*\|?(?:\s*:?-{2,}:?\s*\|)+\s*:?-{2,}:?\s*\|?\s*$")
VAR = re.compile(r"\{\{\s*vars\.(\w+)\s*\}\}")


def front_matter(text: str) -> tuple[dict, str]:
    """Split leading YAML front matter off a card. Flat `key: value` only."""
    if not text.startswith("---\n"):
        return {}, text
    end = text.find("\n---", 3)
    if end == -1:
        return {}, text
    meta = {}
    for line in text[4:end].split("\n"):
        k, sep, v = line.partition(":")
        if sep:
            meta[k.strip()] = v.strip().strip('"').strip("'")
    return meta, text[end + 4:].lstrip("\n")


def title_of(text: str, path: Path) -> str:
    m = re.search(r"^#\s+(.*)$", text, re.M)
    return m.group(1).strip() if m else path.stem


def slug(text: str) -> str:
    s = re.sub(r"<[^>]+>", "", text).lower()
    return re.sub(r"[^a-z0-9]+", "-", s).strip("-") or "section"


def inline(text: str, vars_: dict) -> str:
    """Inline Markdown. Code spans are stashed first so nothing rewrites them."""
    text = VAR.sub(lambda m: vars_.get(m.group(1), m.group(0)), text)
    spans: list[str] = []

    def stash(m: re.Match) -> str:
        spans.append(m.group(1))
        return f"\x00{len(spans) - 1}\x00"

    text = re.sub(r"`([^`]+)`", stash, text)
    text = html_mod.escape(text, quote=False)
    text = re.sub(r"\[([^\]]+)\]\(([^)\s]+)\)",
                  r'<a href="\2" target="_blank" rel="noopener">\1</a>', text)
    text = re.sub(r"&lt;(https?://[^&\s]+)&gt;",
                  r'<a href="\1" target="_blank" rel="noopener">\1</a>', text)
    text = re.sub(r"\*\*([^*]+)\*\*", r"<strong>\1</strong>", text)
    text = re.sub(r"(?<![\w*])\*([^*\n]+)\*(?![\w*])", r"<em>\1</em>", text)
    return re.sub(r"\x00(\d+)\x00",
                  lambda m: f"<code>{html_mod.escape(spans[int(m.group(1))], quote=False)}</code>",
                  text)


def code_block(lang: str, body: str) -> str:
    """A fence. `command` is the copy-me case and is styled as the loud one."""
    kind = lang or "text"
    label = {"command": "command", "output": "expected output",
             "mermaid": "diagram source"}.get(kind, kind)
    copy = "" if kind in NO_COPY_LANGS else '<button class="copy" type="button">Copy</button>'
    return (f'<div class="block block-{html_mod.escape(kind)}">'
            f'<div class="block-bar"><span class="tag">{html_mod.escape(label)}</span>{copy}</div>'
            f'<pre><code>{html_mod.escape(body, quote=False)}</code></pre></div>')


def table(rows: list[str], vars_: dict) -> str:
    def cells(line: str) -> list[str]:
        line = line.strip()
        if line.startswith("|"):
            line = line[1:]
        if line.endswith("|"):
            line = line[:-1]
        return [c.strip() for c in line.split("|")]

    out = ['<div class="table-wrap"><table><thead><tr>']
    out += [f"<th>{inline(c, vars_)}</th>" for c in cells(rows[0])]
    out.append("</tr></thead><tbody>")
    for row in rows[2:]:
        out.append("<tr>" + "".join(f"<td>{inline(c, vars_)}</td>" for c in cells(row)) + "</tr>")
    out.append("</tbody></table></div>")
    return "".join(out)


def render_markdown(text: str, vars_: dict) -> str:
    """This repository's Markdown, to HTML.

    Handles what the documents actually use: labelled fences, ATX headings,
    pipe tables, blockquotes, bullet and numbered lists, rules, and the
    inline set above. Deliberately not handled: nested lists (flattened),
    reference links, footnotes, raw HTML blocks (escaped), and mermaid (shown
    as source). For the full treatment, build the book -- `mvn package` --
    and read the generated pages instead, which is what this view prefers.
    """
    lines = text.split("\n")
    out: list[str] = []
    i, n = 0, len(lines)

    while i < n:
        line = lines[i]

        m = FENCE.match(line)
        if m:
            lang, i = m.group(1), i + 1
            body: list[str] = []
            while i < n and not FENCE.match(lines[i]):
                body.append(lines[i])
                i += 1
            i += 1                                  # the closing fence
            out.append(code_block(lang, "\n".join(body)))
            continue

        m = HEADING.match(line)
        if m:
            level, raw = len(m.group(1)), m.group(2).strip()
            out.append(f'<h{level} id="{slug(raw)}">{inline(raw, vars_)}</h{level}>')
            i += 1
            continue

        if re.match(r"^(---+|\*\*\*+|___+)\s*$", line):
            out.append("<hr>")
            i += 1
            continue

        if "|" in line and i + 1 < n and TABLE_RULE.match(lines[i + 1]):
            rows = [line, lines[i + 1]]
            i += 2
            while i < n and "|" in lines[i] and lines[i].strip():
                rows.append(lines[i])
                i += 1
            out.append(table(rows, vars_))
            continue

        if line.startswith(">"):
            quote: list[str] = []
            while i < n and lines[i].startswith(">"):
                quote.append(lines[i].lstrip(">").strip())
                i += 1
            out.append(f"<blockquote>{inline(' '.join(quote), vars_)}</blockquote>")
            continue

        if BULLET.match(line) or NUMBER.match(line):
            ordered = NUMBER.match(line) is not None
            items: list[str] = []
            while i < n:
                m = NUMBER.match(lines[i]) if ordered else BULLET.match(lines[i])
                if m:
                    items.append(m.group(2))
                    i += 1
                elif lines[i].strip() and lines[i].startswith((" ", "\t")) and items:
                    items[-1] += " " + lines[i].strip()      # continuation
                    i += 1
                else:
                    break
            tag = "ol" if ordered else "ul"
            out.append(f"<{tag}>" + "".join(f"<li>{inline(x, vars_)}</li>" for x in items) + f"</{tag}>")
            continue

        if not line.strip():
            i += 1
            continue

        para: list[str] = []
        while i < n and lines[i].strip() and not FENCE.match(lines[i]) \
                and not HEADING.match(lines[i]) and not lines[i].startswith(">") \
                and not BULLET.match(lines[i]) and not NUMBER.match(lines[i]):
            para.append(lines[i].strip())
            i += 1
        out.append(f"<p>{inline(' '.join(para), vars_)}</p>")

    return "\n".join(out)


def markdown_page(rel: str) -> bytes:
    """A Markdown source as a standalone page, framed the same as a real one."""
    target = safe_join(ROOT, rel)
    if target is None or not target.is_file() or target.suffix != ".md":
        raise FileNotFoundError(rel)
    meta, body = front_matter(target.read_text(encoding="utf-8"))
    title = title_of(body, target)
    oneliner = f'<p class="oneliner">{html_mod.escape(meta.get("oneliner", ""))}</p>' \
        if meta.get("oneliner") else ""
    return (f"""<!doctype html>
<html lang="en"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>{html_mod.escape(title)}</title>
<link rel="stylesheet" href="/_view/doc.css">
</head><body class="md-page"><article id="content">
<p class="source-note">Markdown source — <code>{html_mod.escape(rel)}</code>.
Build the book (<code>mvn package</code>) for the formatted page.</p>
{oneliner}
{render_markdown(body, {"repoUrl": repo_url()})}
</article>
<script src="/_view/launcher.js" defer></script>
</body></html>""").encode("utf-8")


# --- server ------------------------------------------------------------------

ASSETS = {"shell.html": "text/html; charset=utf-8",
          "shell.css": "text/css; charset=utf-8",
          "shell.js": "application/javascript; charset=utf-8",
          "doc.css": "text/css; charset=utf-8",
          "launcher.js": "application/javascript; charset=utf-8"}

LAUNCHER_TAG = b'<script src="/_view/launcher.js" defer></script>'


def inject_launcher(body: bytes) -> bytes:
    """Add launcher.js to a generated page without touching it on disk."""
    if LAUNCHER_TAG in body:
        return body
    lower = body.lower()
    at = lower.rfind(b"</body>")
    if at == -1:
        return body + LAUNCHER_TAG
    return body[:at] + LAUNCHER_TAG + body[at:]


class Handler(BaseHTTPRequestHandler):
    server_version = "workshop-web"
    protocol_version = "HTTP/1.1"

    def log_message(self, fmt, *args):       # quiet: this shares a terminal
        pass

    def _send(self, code: int, body: bytes, ctype: str, extra: dict | None = None) -> None:
        self.send_response(code)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Cache-Control", "no-store")
        for k, v in (extra or {}).items():
            self.send_header(k, v)
        self.end_headers()
        if self.command != "HEAD":
            self.wfile.write(body)

    def _json(self, payload) -> None:
        self._send(200, json.dumps(payload).encode("utf-8"), "application/json")

    def _asset(self, name: str) -> None:
        try:
            self._send(200, (WEB_DIR / name).read_bytes(), ASSETS[name])
        except OSError:
            self._send(404, b"missing view asset", "text/plain; charset=utf-8")

    def _static(self, base: Path, rel: str) -> None:
        target = safe_join(base, rel)
        if target is not None and target.is_dir():
            target = target / "index.html"
        if target is None or not target.is_file():
            self._send(404, b"not found", "text/plain; charset=utf-8")
            return
        ctype = mimetypes.guess_type(target.name)[0] or "application/octet-stream"
        body = target.read_bytes()
        if ctype == "text/html":
            body = inject_launcher(body)
            ctype = "text/html; charset=utf-8"
        self._send(200, body, ctype)

    def do_HEAD(self) -> None:               # noqa: N802
        self.do_GET()

    def do_GET(self) -> None:                # noqa: N802
        parsed = urllib.parse.urlparse(self.path)
        path = urllib.parse.unquote(parsed.path)

        if path in ("/", "/view", "/view/"):
            self._asset("shell.html")
            return

        if path.startswith("/_view/"):
            name = path[len("/_view/"):]
            if name in ASSETS:
                self._asset(name)
            else:
                self._send(404, b"unknown view asset", "text/plain; charset=utf-8")
            return

        if path == "/api/config":
            self._json({"ttydPort": TTYD_PORT, "repoUrl": repo_url(),
                        "source": picker_docs()[1], "sitesBuilt": sites_built()})
            return

        if path == "/api/docs":
            docs, source = picker_docs()
            self._json({"docs": docs, "source": source})
            return

        for prefix, base in SITES.items():
            if path == f"/{prefix}" or path.startswith(f"/{prefix}/"):
                if not base.is_dir():
                    self._send(404, b"the book site is not built: run mvn package",
                               "text/plain; charset=utf-8")
                    return
                self._static(base, path[len(prefix) + 2:] or "index.html")
                return

        if path.startswith("/md/"):
            try:
                self._send(200, markdown_page(path[len("/md/"):]), "text/html; charset=utf-8")
            except (FileNotFoundError, OSError):
                self._send(404, b"no such markdown source", "text/plain; charset=utf-8")
            return

        self._send(404, b"not found", "text/plain; charset=utf-8")


def main() -> int:
    if not (WEB_DIR / "shell.html").exists():
        print(f"error: view assets missing beside {__file__}", file=sys.stderr)
        return 1
    docs, source = picker_docs()
    server = ThreadingHTTPServer(("0.0.0.0", WEB_PORT), Handler)
    print(f"instructions on http://localhost:{WEB_PORT}  "
          f"({len(docs)} pages, {source})", flush=True)
    if source == "markdown":
        print("note: target/site is not built, so the Markdown sources are being "
              "served. Run `mvn package` for the generated pages.", flush=True)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    return 0


if __name__ == "__main__":
    sys.exit(main())
