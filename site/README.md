# The website

The source of https://tuna-nope.github.io/macbox/, built by `build.py` (Python's standard library,
nothing to install) and published to GitHub Pages by `.github/workflows/pages.yml` on every push
to main that touches it.

```sh
python3 site/build.py           # build into site/_site and check it
python3 site/build.py --serve   # the same, then http://127.0.0.1:8000/macbox/
```

| | |
|---|---|
| `pages/` | one HTML fragment per page. A header of `key: value` lines, then `---`. The file's path is the URL: `pages/guides/xcode-on-linux.html` is `/guides/xcode-on-linux/` |
| `layout.html`, `style.css` | the frame around every page; the CSS is inlined |
| `static/` | copied as is: the favicon, the IndexNow key, search engines' verification files, and the home page's picture, made from `docs/images/hero.jpg` without its empty top 21 px: `magick docs/images/hero.jpg -crop 1600x923+0+21 +repage` then `-quality 82 hero-1600.webp`, `-resize 800x -quality 80 hero-800.webp` and `-quality 84 -interlace JPEG hero-1600.jpg` in `static/images/`; remake them when the picture changes) |

The repo stays the source of truth. The guides answer one question each and link to `docs/` for the
full reference; pictures (`docs/images`) and `llms.txt` are copied from the repo at build time, not
kept twice. When a command or a number changes in the docs, change it in the guides that show it.

**Adding a guide:** a new file in `pages/guides/` with `title`, `short` (the breadcrumb),
`description` (50 to 165 characters, unique), `kind: guide`, `order` and `updated: YYYY-MM-DD`.
The guide lists, the sitemap and the structured data pick it up. Add it to `llms.txt` too.

**The build fails on:** a broken internal link or `#anchor`, a missing or duplicate title or
description, a page without exactly one `<h1>`, and a `macbox <command>` or `mac-sim <command>` in
a code sample that the CLI doesn't have.

Every page also gets a Markdown copy (`index.md` beside `index.html`) for language models, as
llmstxt.org suggests. robots.txt can't be set here: crawlers read it only at the host's root
(`tuna-nope.github.io/robots.txt`), which this repo doesn't control. Pages carry robots meta tags.
