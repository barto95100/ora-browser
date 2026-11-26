import WebKit

/// Reader mode's part in the page: whether the page holds an article, and
/// the article itself, rebuilt from scratch. In its own world: the page
/// can't see or call it, and it changes nothing in the page's document.
///
/// The article is made again element by element from a short list of tags
/// (paragraphs, headings, lists, quotes, code, tables, figures, links,
/// images) with only the attributes they need, absolute addresses and no
/// style, script, frame or form: what the reader shows can't run anything,
/// and has none of the page's look.
enum ReaderScript {
    @MainActor static let world = WKContentWorld.world(name: "reader")

    /// Installs `window.__ombreReader` in the reader's world (once per document).
    static let source = #"""
    (() => {
    if (window.__ombreReader) return;
    """# + markdownSource + detailsSource + editLinksSource + #"""

    const negative = new RegExp("(^|[-_ ])(" + [
        "comment", "comments", "meta", "footer", "footnotes", "sidebar", "widget", "share", "sharing", "social",
        "related", "recommended", "recommendations", "promo", "sponsor", "sponsored", "ad", "ads", "advert",
        "advertisement", "banner", "nav", "navbar", "menu", "breadcrumb", "breadcrumbs", "masthead", "subscribe",
        "newsletter", "signup", "cookie", "consent", "popup", "modal", "outbrain", "taboola", "tags", "pagination",
        "pager", "toolbar", "skip", "hidden", "print", "author-bio", "more-stories", "most-read"
    ].join("|") + ")([-_ ]|$)", "i");
    const positive = new RegExp("(^|[-_ ])(" + [
        "article", "body", "content", "entry", "main", "post", "text", "blog", "story", "prose", "markdown"
    ].join("|") + ")([-_ ]|$)", "i");

    function clean(text) {
        return (text || "").replace(/\s+/g, " ").trim();
    }

    function hint(element) {
        const className = typeof element.className === "string" ? element.className : "";
        return className + " " + (element.id || "");
    }

    function weight(element) {
        const words = hint(element);
        return (positive.test(words) ? 25 : 0) - (negative.test(words) ? 25 : 0);
    }

    function isHidden(element) {
        if (element.hidden || element.getAttribute("aria-hidden") === "true") return true;
        const style = getComputedStyle(element);
        return style.display === "none" || style.visibility === "hidden";
    }

    function linkDensity(element) {
        const total = clean(element.textContent).length;
        if (!total) return 0;
        let links = 0;
        element.querySelectorAll("a").forEach(link => { links += clean(link.textContent).length; });
        return Math.min(1, links / total);
    }

    // Like Safari's button: enough paragraphs of real text.
    function isReadable() {
        let score = 0;
        for (const paragraph of document.querySelectorAll("p, pre, article div")) {
            if (paragraph.localName === "div" && paragraph.querySelector("p, div")) continue;
            const length = clean(paragraph.textContent).length;
            if (length < 140 || isHidden(paragraph)) continue;
            if (paragraph.closest("nav, aside, footer, form, [role=navigation], [role=complementary]")) continue;
            score += Math.sqrt(length - 140);
            if (score > 20) return true;
        }
        return false;
    }

    // The block holding the article: the one its paragraphs add up in.
    function findRoot() {
        const scores = new Map();
        function add(element, points) {
            if (!scores.has(element)) {
                let base = weight(element);
                if (element.localName === "article" || element.getAttribute("itemprop") === "articleBody") base += 10;
                if (["div", "section", "main"].includes(element.localName)) base += 5;
                const lists = ["form", "ul", "ol", "dl", "header", "footer", "nav", "aside"];
                if (lists.includes(element.localName)) base -= 5;
                scores.set(element, base);
            }
            scores.set(element, scores.get(element) + points);
        }
        for (const paragraph of document.querySelectorAll("p, pre")) {
            const text = clean(paragraph.textContent);
            if (text.length < 25 || isHidden(paragraph)) continue;
            const parent = paragraph.parentElement;
            if (!parent || parent === document.documentElement) continue;
            const points = 1 + text.split(/[,،，、]/).length - 1 + Math.min(Math.floor(text.length / 100), 3);
            add(parent, points);
            const grandparent = parent.parentElement;
            if (grandparent && grandparent !== document.documentElement) add(grandparent, points / 2);
        }
        let best = null;
        let bestScore = 0;
        const final = element => (scores.get(element) || 0) * (1 - linkDensity(element));
        for (const element of scores.keys()) {
            const score = final(element);
            if (score > bestScore) { best = element; bestScore = score; }
        }
        if (!best) return null;
        // An article cut into sections, one per heading (Wikipedia's): all
        // of them, the introduction before the first heading included. Only
        // sections led by a heading, not comments or related stories.
        const isHeaded = element => {
            const first = element.firstElementChild;
            return !!first && (/^h[2-6]$/.test(first.localName) || first.classList.contains("mw-heading"));
        };
        while (best.localName === "section" && isHeaded(best) && best.parentElement) {
            const parent = best.parentElement;
            if (parent === document.body || parent === document.documentElement) break;
            const sections = Array.from(parent.children).filter(child => child !== best
                && child.localName === "section" && isHeaded(child) && weight(child) >= 0 && child.querySelector("p"));
            if (!sections.length) break;
            best = parent;
        }
        // A parent nearly as good holds more of it (title, figures, paragraphs in their own blocks).
        for (let step = 0; step < 3; step += 1) {
            const parent = best.parentElement;
            if (!parent || parent === document.body || parent === document.documentElement) break;
            if (final(parent) < bestScore * 0.75) break;
            best = parent;
        }
        return best;
    }

    const kept = new Set([
        "p", "h1", "h2", "h3", "h4", "h5", "h6", "ul", "ol", "li", "blockquote", "pre", "code", "em", "strong",
        "b", "i", "u", "s", "mark", "small", "sub", "sup", "a", "img", "figure", "figcaption", "table", "thead",
        "tbody", "tfoot", "tr", "th", "td", "caption", "br", "hr", "dl", "dt", "dd", "abbr", "cite", "q",
        "time", "kbd", "var", "del", "ins"
    ]);
    const blocks = new Set(["div", "section", "article", "main", "center", "details", "summary"]);
    const dropped = new Set([
        "script", "style", "noscript", "template", "iframe", "frame", "object", "embed", "form", "input", "button",
        "select", "textarea", "nav", "aside", "footer", "header", "svg", "canvas", "dialog", "link", "meta",
        "audio", "video", "map", "math", "slot"
    ]);

    function absolute(address, schemes) {
        try {
            const url = new URL(address, document.baseURI);
            return schemes.includes(url.protocol) ? url.href : null;
        } catch (e) {
            return null;
        }
    }

    // The image's real address: pages that load them late keep it aside.
    function imageSource(image) {
        const candidates = [image.currentSrc, image.getAttribute("src")];
        for (const name of ["data-src", "data-lazy-src", "data-original", "data-url", "data-hi-res-src"]) {
            candidates.push(image.getAttribute(name));
        }
        const set = image.getAttribute("srcset") || image.getAttribute("data-srcset");
        if (set) {
            const last = set.split(",").map(part => part.trim().split(/\s+/)[0]).filter(Boolean).pop();
            candidates.push(last);
        }
        for (const candidate of candidates) {
            if (!candidate || /^data:/.test(candidate) && candidate.length < 200) continue;
            const url = absolute(candidate, ["http:", "https:", "data:"]);
            if (url && (!url.startsWith("data:") || /^data:image\//.test(url))) return url;
        }
        return null;
    }

    // A tracking pixel or an icon. The size loaded tells only for the image
    // kept (a page's placeholder is often 1 × 1).
    function isTiny(image, source) {
        const loaded = image.complete && image.currentSrc === source;
        const width = Number(image.getAttribute("width")) || (loaded ? image.naturalWidth : 0);
        const height = Number(image.getAttribute("height")) || (loaded ? image.naturalHeight : 0);
        return (width && width < 48) || (height && height < 48);
    }

    // An element of the page's article in the reader's own document, or
    // its children only (a wrapper), or nothing.
    // The byline shown by the reader above the article: not again in it.
    let bylineElement = null;

    function rebuild(node, into, title) {
        if (node.nodeType === Node.TEXT_NODE) {
            into.appendChild(document.createTextNode(node.textContent));
            return;
        }
        if (node.nodeType !== Node.ELEMENT_NODE) return;
        const tag = node.localName;
        if (dropped.has(tag) || node === bylineElement || isHidden(node)) return;
        if (notArticle.test(hint(node)) || isOnlyEditLinks(node)) return;
        // A heading's own edit link ("History [edit]").
        if (tag === "a" && editWords.test(clean(node.textContent)) && node.closest("h1, h2, h3, h4, h5, h6")) return;
        // Share buttons, related stories, comments: little text or mostly links.
        if (weight(node) < 0 && node.querySelectorAll("img").length < 3) {
            const length = clean(node.textContent).length;
            if (length < 400 || linkDensity(node) > 0.3) return;
        }
        if (tag === "picture") {
            const image = node.querySelector("img");
            if (image) rebuild(image, into, title);
            return;
        }
        if (tag === "img") {
            const source = imageSource(node);
            if (!source || isTiny(node, source)) return;
            const image = document.createElement("img");
            image.setAttribute("src", source);
            const alt = clean(node.getAttribute("alt"));
            if (alt) image.setAttribute("alt", alt);
            into.appendChild(image);
            return;
        }
        if (/^h[1-6]$/.test(tag) && clean(node.textContent) === title) return;
        let element = null;
        if (kept.has(tag)) {
            element = document.createElement(tag);
            if (tag === "a") {
                const href = absolute(node.getAttribute("href") || "", ["http:", "https:", "mailto:"]);
                if (!href) element = null;
                else element.setAttribute("href", href);
            } else if (tag === "td" || tag === "th") {
                for (const name of ["colspan", "rowspan"]) {
                    const value = node.getAttribute(name);
                    if (value && /^\d{1,3}$/.test(value)) element.setAttribute(name, value);
                }
            } else if (tag === "ol" && /^\d{1,6}$/.test(node.getAttribute("start") || "")) {
                element.setAttribute("start", node.getAttribute("start"));
            } else if (tag === "time" && node.getAttribute("datetime")) {
                element.setAttribute("datetime", node.getAttribute("datetime").slice(0, 40));
            } else if (tag === "pre" || tag === "code") {
                // Code keeps its own spacing: copied as text.
                if (tag === "pre") {
                    element.textContent = node.textContent;
                    into.appendChild(element);
                    return;
                }
            }
        } else if (blocks.has(tag)) {
            element = document.createElement("div");
        }
        const target = element || into;
        for (const child of node.childNodes) rebuild(child, target, title);
        if (!element) return;
        // An emptied block (its contents were dropped): not kept.
        const empty = !clean(element.textContent) && !element.querySelector("img, hr, br")
            && !["img", "hr", "br"].includes(tag);
        if (!empty) into.appendChild(element);
    }

    function extract() {
        const root = findRoot();
        if (!root) return null;
        const title = findTitle(root);
        const byline = findByline(root);
        const content = document.createElement("div");
        // Its children: the block itself is kept whatever its name says.
        for (const child of root.childNodes) rebuild(child, content, title);
        const text = clean(content.textContent);
        if (text.length < 200) return null;
        // The contents: its headings, each with an anchor of the reader's own.
        const headings = Array.from(content.querySelectorAll("h2, h3")).map((heading, index) => {
            heading.setAttribute("id", "ombre-heading-" + (index + 1));
            return { level: Number(heading.localName.slice(1)), text: clean(heading.textContent), id: heading.id };
        }).filter(heading => heading.text);
        const images = Array.from(content.querySelectorAll("img")).map(image => image.getAttribute("src"));
        const words = text.split(" ").length;
        return {
            title: title,
            byline: byline,
            site: meta("og:site_name", "application-name") || location.hostname.replace(/^www\./, ""),
            published: findDate(root),
            lang: document.documentElement.lang || null,
            dir: document.dir || document.documentElement.dir || null,
            html: content.innerHTML,
            markdown: markdown(content, 0).replace(/[ \t]+\n/g, "\n").replace(/\n{3,}/g, "\n\n").trim(),
            images: Array.from(new Set(images)),
            headings: headings,
            words: words
        };
    }

    window.__ombreReader = { isReadable: isReadable, findRoot: findRoot, extract: extract };
    })();
    """#

    /// Calls `body` with `reader` bound to the script's API.
    static func script(_ body: String) -> String {
        source + "\nconst reader = window.__ombreReader;\n" + body // not shown
    }
}
