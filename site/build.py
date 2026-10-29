#!/usr/bin/env python3
"""Builds macbox's website (GitHub Pages) into site/_site. Standard library only.

  python3 site/build.py            build, then check the output (fails on any problem)
  python3 site/build.py --serve    build, then serve it at http://127.0.0.1:8000/macbox/ (PORT=... for another port)

Pages are HTML fragments in site/pages/, each with a header of `key: value` lines ended by `---`
(title, description, and for guides: kind: guide, short, updated). A page's URL is its path:
pages/guides/xcode-on-linux.html -> /guides/xcode-on-linux/. Links inside pages are written from
the site's root (href="/guides/"); the build prefixes BASE_PATH. Pictures and llms.txt come
from the repo itself (docs/images, llms.txt), so they have one source.
"""
import datetime, html, json, os, re, shutil, sys
from pathlib import Path

SITE_URL = os.environ.get("MACBOX_SITE_URL", "https://tuna-nope.github.io/macbox").rstrip("/")
BASE_PATH = "/" + SITE_URL.split("://", 1)[1].partition("/")[2] if "/" in SITE_URL.split("://", 1)[1] else ""
BASE_PATH = BASE_PATH.rstrip("/")
REPO_URL = "https://github.com/TUNA-NOPE/macbox"
NAME = "macbox"

HERE = Path(__file__).resolve().parent
ROOT = HERE.parent
OUT = HERE / "_site"
FROM_REPO = {  # repo file -> path in the site
    "docs/images/social-preview.jpg": "images/social-preview.jpg",
    "docs/images/fps-light.svg": "images/fps-light.svg",
    "docs/images/fps-dark.svg": "images/fps-dark.svg",
    "llms.txt": "llms.txt",
}
NAV = [("/", "Overview"), ("/guides/", "Guides"), ("/#performance", "Performance"),
       (REPO_URL + "/blob/main/docs/setup.md", "Docs")]


def read_page(path):
    text = path.read_text()
    head, sep, body = text.partition("\n---\n")
    if not sep:
        sys.exit(f"{path}: no header (key: value lines, then ---)")
    meta = dict(line.split(": ", 1) for line in head.strip().splitlines())
    rel = path.relative_to(HERE / "pages").with_suffix("")
    if rel.name == "index":
        url = "/" + (str(rel.parent) + "/" if str(rel.parent) != "." else "")
    elif rel.name == "404":
        url = "/404.html"
    else:
        url = f"/{rel}/"
    meta.update(url=url, body=body, src=path)
    return meta


def link(url):  # a path from the site's root -> one under BASE_PATH
    return BASE_PATH + url


def absolute(url):
    return SITE_URL + url


def json_ld(page, guides):
    graph = []
    crumbs = [("/", "macbox")]
    if page["url"] == "/":
        graph.append({
            "@type": "WebSite", "@id": absolute("/#website"), "url": absolute("/"), "name": NAME,
            "description": page["description"], "inLanguage": "en"})
        graph.append({
            "@type": "SoftwareSourceCode", "@id": absolute("/#software"), "name": NAME,
            "description": page["description"], "url": absolute("/"), "codeRepository": REPO_URL,
            "programmingLanguage": ["Bash", "Python", "Swift"], "runtimePlatform": "Linux (x86-64, KVM, Docker)",
            "targetProduct": {"@type": "SoftwareApplication", "name": NAME, "operatingSystem": "Linux",
                              "applicationCategory": "DeveloperApplication"},
            "license": "https://polyformproject.org/licenses/noncommercial/1.0.0/",
            "image": absolute("/images/social-preview.jpg")})
        return graph
    if page.get("kind") == "guide":
        crumbs.append(("/guides/", "Guides"))
        graph.append({
            "@type": "TechArticle", "headline": page["title"], "description": page["description"],
            "url": absolute(page["url"]), "mainEntityOfPage": absolute(page["url"]),
            "datePublished": page["published"] + "T00:00:00Z", "dateModified": page["updated"] + "T00:00:00Z",
            "inLanguage": "en", "image": absolute("/images/social-preview.jpg"),
            "author": {"@type": "Organization", "name": "macbox", "url": REPO_URL},
            "about": {"@type": "SoftwareSourceCode", "@id": absolute("/#software"), "name": NAME,
                      "codeRepository": REPO_URL, "url": absolute("/")},
            "isPartOf": {"@type": "WebSite", "@id": absolute("/#website"), "name": NAME, "url": absolute("/")}})
    crumbs.append((page["url"], page.get("short", page["title"])))
    graph.append({"@type": "BreadcrumbList", "itemListElement": [
        {"@type": "ListItem", "position": i + 1, "name": n, "item": absolute(u)} for i, (u, n) in enumerate(crumbs)]})
    return graph


def guide_list(guides, exclude=None):
    items = []
    for g in guides:
        if g["url"] == exclude:
            continue
        items.append(f'<li><a href="{g["url"]}"><strong>{html.escape(g["title"])}</strong>'
                     f'<span>{html.escape(g["description"])}</span></a></li>')
    return '<ul class="cards">' + "".join(items) + "</ul>"


def render(page, guides, layout, css):
    body = page["body"].replace("{{guides}}", guide_list(guides))
    body = re.sub(r"&(?![a-zA-Z]+;|#\d+;|#[xX][0-9a-fA-F]+;)", "&amp;", body)  # `&&` in commands, written plainly in the pages
    body = re.sub(r"<thead>.*?</thead>", lambda m: m.group(0).replace("<th>", '<th scope="col">').replace('<th class="', '<th scope="col" class="'), body, flags=re.S)
    body = re.sub(r"<tbody>.*?</tbody>", lambda m: m.group(0).replace("<th>", '<th scope="row">'), body, flags=re.S)
    is_guide = page.get("kind") == "guide"
    if is_guide:
        crumbs = (f'<nav class="crumbs" aria-label="Breadcrumb"><a href="/">macbox</a> <span>/</span> '
                  f'<a href="/guides/">Guides</a></nav>')
        updated = page["updated"]
        stamp = (f'<p class="meta">Updated <time datetime="{updated}">'
                 f'{datetime.date.fromisoformat(updated).strftime("%-d %B %Y")}</time> · '
                 f'Source of truth: the <a href="{REPO_URL}">repository</a> and its docs</p>')
        body = body.replace("<h1>", crumbs + "<h1>", 1).replace("{{meta}}", stamp, 1)
        body += ('<aside class="related"><h2>More guides</h2>' + guide_list(guides, page["url"]) + "</aside>")
    current = ' aria-current="page"'
    nav = "".join(f'<a href="{u}"{current if u == page["url"] else ""}>{n}</a>' for u, n in NAV)
    title = page["title"] if page["url"] == "/" else f'{page["title"]} · macbox'
    ld = json.dumps({"@context": "https://schema.org", "@graph": json_ld(page, guides)}, ensure_ascii=False) \
        if page["url"] != "/404.html" else None
    out = (layout
           .replace("{{css}}", css)
           .replace("{{title}}", html.escape(title))
           .replace("{{description}}", html.escape(page["description"], quote=True))
           .replace("{{og_type}}", "article" if is_guide else "website")
           .replace("{{robots}}", "noindex" if page["url"] == "/404.html" else "index, follow, max-image-preview:large")
           .replace("{{verification}}", verification_meta())
           .replace("{{markdown}}", f'<link rel="alternate" type="text/markdown" href="{page["url"]}index.md">'
                    if page["url"].endswith("/") else "")
           .replace("{{json_ld}}", f'<script type="application/ld+json">{ld}</script>' if ld else "")
           .replace("{{nav}}", nav)
           .replace("{{repo}}", REPO_URL)
           .replace("{{year}}", str(datetime.date.today().year))
           .replace("{{body}}", body))
    canonical = absolute(page["url"]) if page["url"] != "/404.html" else ""
    out = out.replace("{{canonical}}", f'<link rel="canonical" href="{canonical}">' if canonical else "")
    out = out.replace("{{url}}", canonical or SITE_URL + "/")
    out = out.replace("{{site}}", SITE_URL)
    # links from the site's root get the base path; external and #-links stay as they are
    out = re.sub(r'(href|src)="/(?!/)', lambda m: f'{m.group(1)}="{BASE_PATH}/', out)
    # srcset holds a list ("/a.webp 800w, /b.webp 1600w"): prefix every candidate, not just the first
    out = re.sub(r'srcset="([^"]+)"', lambda m: 'srcset="' + re.sub(r'(^|,\s*)/(?!/)', rf'\1{BASE_PATH}/', m.group(1)) + '"', out)
    return out


def verification_meta():
    tags = []
    for env, name in (("GOOGLE_SITE_VERIFICATION", "google-site-verification"), ("BING_SITE_VERIFICATION", "msvalidate.01")):
        token = (HERE / "verification" / env.lower()).read_text().strip() if (HERE / "verification" / env.lower()).exists() else ""
        if token:
            tags.append(f'<meta name="{name}" content="{html.escape(token, quote=True)}">')
    return "".join(tags)


class Markdown(__import__("html.parser").parser.HTMLParser):
    """The subset of HTML the pages use -> Markdown, for the .md copy of each page (llmstxt.org)."""
    BLOCK = {"p", "h1", "h2", "h3", "li", "pre", "summary", "figcaption", "details", "div", "figure"}

    def __init__(self):
        super().__init__(convert_charrefs=True)
        self.out, self.href, self.lists, self.pre, self.cells, self.row, self.skip = [], [], [], False, None, 0, 0

    def handle_starttag(self, tag, attrs):
        a = dict(attrs)
        if tag in ("script", "style", "svg") or (tag == "nav" and a.get("class") == "crumbs"):
            self.skip += 1
        if self.skip:
            return
        if tag in self.BLOCK or tag in ("ul", "ol", "table"):
            self.out.append("\n\n")
        if tag in ("h1", "h2", "h3"):
            self.out.append("#" * int(tag[1]) + " ")
        elif tag in ("ul", "ol"):
            self.lists.append([tag, 0])
        elif tag == "li":
            kind = self.lists[-1] if self.lists else ["ul", 0]
            kind[1] += 1
            self.out[-1] = "\n" + "  " * (len(self.lists) - 1)
            self.out.append(f"{kind[1]}. " if kind[0] == "ol" else "- ")
        elif tag == "pre":
            self.pre = True
            self.out.append("```sh\n")
        elif tag == "code" and not self.pre:
            self.out.append("`")
        elif tag in ("strong", "b") and not self.pre:
            self.out.append("**")
        elif tag == "a":
            self.href.append(a.get("href", ""))
            self.out.append("[")
        elif tag == "img" and a.get("alt"):
            self.out.append(f"![{a['alt']}]({a.get('src', '')})")
        elif tag == "tr":
            self.cells, self.row_start = [], len(self.out)
        elif tag in ("td", "th") and self.cells is not None:
            self.out.append("\x00")
        elif tag == "summary":
            self.out.append("### ")

    def handle_endtag(self, tag):
        if tag in ("script", "style", "svg", "nav") and self.skip:
            self.skip -= 1
            return
        if self.skip:
            return
        if tag in ("ul", "ol") and self.lists:
            self.lists.pop()
        elif tag == "pre":
            self.pre = False
            self.out.append("\n```\n\n")
        elif tag == "code" and not self.pre:
            self.out.append("`")
        elif tag in ("strong", "b") and not self.pre:
            self.out.append("**")
        elif tag == "a" and self.href:
            self.out.append(f"]({self.href.pop()})")
        elif tag == "tr":
            text = "".join(self.out[self.row_start:])
            cells = [c.strip().replace("\n", " ").replace("|", "\\|") for c in text.split("\x00")[1:]]
            del self.out[self.row_start:]
            line = "| " + " | ".join(cells) + " |"
            if self.row == 0:
                line += "\n|" + "---|" * len(cells)
            self.row += 1
            self.out.append(line + "\n")
            self.cells = None
        elif tag == "table":
            self.row = 0

    def handle_data(self, data):
        if self.skip:
            return
        self.out.append(data if self.pre else re.sub(r"\s+", " ", data))

    def text(self):
        md = "".join(self.out)
        md = re.sub(r"\n[ \t]+\n", "\n\n", md)
        md = re.sub(r"\n{3,}", "\n\n", md)
        lines, fenced = [], False
        for line in md.strip().splitlines():
            if line.startswith("```"):
                fenced = not fenced
            elif not fenced and not re.match(r"\s+(- |\d+\. )", line):
                line = line.lstrip()
            lines.append(line.rstrip())
        return re.sub(r"\n{3,}", "\n\n", "\n".join(lines)) + "\n"


def markdown_copy(page, rendered_body):
    m = Markdown()
    m.feed(rendered_body)
    head = f"<!-- {absolute(page['url'])} — the HTML page is the canonical version -->\n\n"
    return head + m.text()


def sitemap(pages):
    rows = []
    rank = lambda p: (p["url"] != "/", p["url"] != "/guides/", int(p.get("order", 99)), p["url"])
    for p in sorted(pages, key=rank):
        if p["url"] == "/404.html":
            continue
        rows.append(f"  <url><loc>{absolute(p['url'])}</loc><lastmod>{p['updated']}</lastmod></url>")
    return ('<?xml version="1.0" encoding="UTF-8"?>\n<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">\n'
            + "\n".join(rows) + "\n</urlset>\n")


def build():
    pages = [read_page(p) for p in sorted((HERE / "pages").rglob("*.html"))]
    for p in pages:
        p.setdefault("updated", "2026-10-29")
        p.setdefault("published", p["updated"])
    guides = sorted((p for p in pages if p.get("kind") == "guide"), key=lambda p: int(p.get("order", 99)))
    layout = (HERE / "layout.html").read_text()
    css = (HERE / "style.css").read_text()
    css = re.sub(r"/\*.*?\*/", "", css, flags=re.S)
    css = re.sub(r"\s*\n\s*", "\n", css).strip()
    if OUT.exists():
        shutil.rmtree(OUT)
    OUT.mkdir()
    for p in pages:
        dest = OUT / (p["url"].lstrip("/") + ("index.html" if p["url"].endswith("/") else ""))
        dest.parent.mkdir(parents=True, exist_ok=True)
        page_html = render(p, guides, layout, css)
        dest.write_text(page_html)
        if p["url"].endswith("/"):
            main = page_html.split('<main id="main">', 1)[1].split("</main>", 1)[0]
            main = re.sub(r'(href|src)="/(?!/)', lambda m: f'{m.group(1)}="{SITE_URL[:-len(BASE_PATH)] if BASE_PATH else SITE_URL}/', main)
            (dest.parent / "index.md").write_text(markdown_copy(p, main))
    for src, dst in FROM_REPO.items():
        (OUT / dst).parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(ROOT / src, OUT / dst)
    shutil.copytree(HERE / "static", OUT, dirs_exist_ok=True)
    (OUT / "sitemap.xml").write_text(sitemap(pages))
    (OUT / ".nojekyll").write_text("")
    return pages


# ---- checks: run on every build, so a broken link or a command that doesn't exist fails CI ----

def cli_commands(script):  # the subcommands a script's top-level `case` dispatches
    found = re.findall(r"^  ([a-z0-9|-]+)\) ?", (ROOT / script).read_text(), flags=re.M)
    return {w for line in found for w in line.split("|")}


def check(pages):
    problems = []
    seen_titles, seen_desc = {}, {}
    macbox_cmds = cli_commands("macbox")
    macsim_cmds = cli_commands("sims/bin/mac-sim")
    files = {str(f.relative_to(OUT)) for f in OUT.rglob("*") if f.is_file()}
    for p in pages:
        for key in ("title", "description"):
            if key not in p:
                problems.append(f"{p['src'].name}: no {key}")
        if not 50 <= len(p.get("description", "")) <= 165:
            problems.append(f"{p['src'].name}: description is {len(p.get('description', ''))} characters (50 to 165)")
        for key, seen in (("title", seen_titles), ("description", seen_desc)):
            if p.get(key) in seen:
                problems.append(f"{p['src'].name}: same {key} as {seen[p[key]]}")
            seen[p.get(key)] = p["src"].name
        if p["url"] != "/404.html" and p["body"].count("<h1") != 1:
            problems.append(f"{p['src'].name}: needs exactly one <h1>")
        # every command the page shows must exist in the CLI it names
        for block in re.findall(r"<code[^>]*>(.*?)</code>", p["body"], flags=re.S):
            text = html.unescape(re.sub(r"<[^>]+>", "", block))
            for tool, known in (("macbox", macbox_cmds), ("mac-sim", macsim_cmds)):
                # in command position: a line's start, after && ; | & or ./ (not `ssh macbox ...`, the SSH alias)
                pattern = rf"(?:^|&&|;|\||&|\./)\s*(?<!ssh ){re.escape(tool)} ([a-z][a-z0-9-]*)"
                for sub in set(re.findall(pattern, text, flags=re.M)):
                    if sub not in known:
                        problems.append(f"{p['src'].name}: `{tool} {sub}` isn't a {tool} command")
    for f in OUT.rglob("*.html"):
        text = f.read_text()
        refs = re.findall(r'(?:href|src)="([^"]+)"', text)
        refs += [c.split()[0] for v in re.findall(r'srcset="([^"]+)"', text) for c in v.split(",")]
        for ref in refs:
            if ref.startswith(("http://", "https://", "mailto:", "#", "data:")):
                continue
            if not ref.startswith(BASE_PATH + "/"):
                problems.append(f"{f.relative_to(OUT)}: link outside the site's base path: {ref}")
                continue
            target = ref[len(BASE_PATH) + 1:].split("#")[0].split("?")[0]
            if target == "" or target.endswith("/"):
                target += "index.html"
            if target not in files:
                problems.append(f"{f.relative_to(OUT)}: broken link {ref}")
            elif "#" in ref and (frag := ref.split("#", 1)[1]):
                if f'id="{frag}"' not in (OUT / target).read_text():
                    problems.append(f"{f.relative_to(OUT)}: no #{frag} in {target}")
    return problems


def serve():
    import http.server, functools, tempfile
    root = Path(tempfile.mkdtemp())
    (root / BASE_PATH.strip("/")).symlink_to(OUT) if BASE_PATH else None
    handler = functools.partial(http.server.SimpleHTTPRequestHandler, directory=str(root if BASE_PATH else OUT))
    port = int(os.environ.get("PORT", 8000))
    print(f"http://127.0.0.1:{port}{BASE_PATH}/", flush=True)
    http.server.ThreadingHTTPServer(("127.0.0.1", port), handler).serve_forever()


if __name__ == "__main__":
    built = build()
    issues = check(built)
    for i in issues:
        print("problem:", i, file=sys.stderr)
    if issues:
        sys.exit(1)
    print(f"built {len(built)} pages into {OUT.relative_to(ROOT)}")
    if "--serve" in sys.argv:
        serve()
