import Foundation

extension ReaderScript {
    /// The article as Markdown, for a note (a part of `source`).
    static let markdownSource = #"""
    // The article as Markdown, for a note.
    function markdown(node, depth) {
        let out = "";
        for (const child of node.childNodes) out += markdownOf(child, depth);
        return out;
    }

    function inline(node) {
        return markdown(node, 0).replace(/\s+/g, " ").trim();
    }

    function escapeText(text) {
        return text.replace(/([\\`*_\[\]<>#])/g, "\\$1");
    }

    function markdownOf(node, depth) {
        if (node.nodeType === Node.TEXT_NODE) return escapeText(node.textContent.replace(/\s+/g, " "));
        if (node.nodeType !== Node.ELEMENT_NODE) return "";
        const tag = node.localName;
        switch (tag) {
        case "h1": case "h2": case "h3": case "h4": case "h5": case "h6":
            return "\n\n" + "#".repeat(Math.min(6, Number(tag[1]) + 1)) + " " + inline(node) + "\n\n";
        case "p": case "div": case "figure": case "table": case "dl":
            return "\n\n" + markdown(node, depth).trim() + "\n\n";
        case "figcaption": case "caption":
            return "\n\n*" + inline(node) + "*\n\n";
        case "br":
            return "  \n";
        case "hr":
            return "\n\n---\n\n";
        case "strong": case "b": {
            const text = inline(node);
            return text ? "**" + text + "**" : "";
        }
        case "em": case "i": case "cite": {
            const text = inline(node);
            return text ? "*" + text + "*" : "";
        }
        case "code":
            return "`" + node.textContent.replace(/`/g, "") + "`";
        case "pre":
            return "\n\n```\n" + node.textContent.replace(/```/g, "ˋˋˋ").replace(/\n+$/, "") + "\n```\n\n";
        case "a": {
            const text = inline(node);
            const href = node.getAttribute("href");
            if (!text) return markdown(node, depth);
            return href ? "[" + text + "](" + href.replace(/\)/g, "%29").replace(/ /g, "%20") + ")" : text;
        }
        case "img": {
            const alt = (node.getAttribute("alt") || "").replace(/[\[\]]/g, "");
            const source = node.getAttribute("src").replace(/\)/g, "%29").replace(/ /g, "%20");
            return "\n\n![" + alt + "](" + source + ")\n\n";
        }
        case "blockquote":
            return "\n\n" + markdown(node, depth).trim().split("\n").map(line => "> " + line).join("\n") + "\n\n";
        case "ul": case "ol": {
            let index = Number(node.getAttribute("start")) || 1;
            let out = "\n\n";
            for (const item of node.children) {
                if (item.localName !== "li") continue;
                const marker = tag === "ol" ? (index++) + ". " : "- ";
                const body = markdown(item, depth + 1).trim().replace(/\n{2,}/g, "\n")
                    .split("\n").join("\n" + "  ".repeat(depth + 1));
                out += "  ".repeat(depth) + marker + body + "\n";
            }
            return out + "\n";
        }
        case "tr":
            return "\n" + Array.from(node.children).map(cell => inline(cell)).join(" · ");
        case "dt":
            return "\n\n**" + inline(node) + "**\n";
        case "dd":
            return "\n" + inline(node) + "\n";
        default:
            return markdown(node, depth);
        }
    }
    """#

    /// The article's title, author and date, from the page (a part of `source`).
    static let detailsSource = #"""
    function meta(...names) {
        for (const name of names) {
            const element = document.querySelector(`meta[property="${name}"], meta[name="${name}"]`);
            const content = clean(element && element.getAttribute("content"));
            if (content) return content;
        }
        return null;
    }

    function findTitle(root) {
        const shared = meta("og:title", "twitter:title");
        const inRoot = root ? Array.from(root.querySelectorAll("h1")).filter(heading => !isHidden(heading)) : [];
        const headings = Array.from(new Set(inRoot.concat(Array.from(document.querySelectorAll("h1")))))
            .filter(heading => !isHidden(heading));
        const documentTitle = clean(document.title);
        for (const heading of headings) {
            const text = clean(heading.textContent);
            if (text.length >= 4 && (documentTitle.includes(text) || (shared && shared.includes(text)))) return text;
        }
        if (shared) return shared;
        // The article's own heading, else the page's only one.
        if (inRoot.length && clean(inRoot[0].textContent)) return clean(inRoot[0].textContent);
        if (headings.length === 1) return clean(headings[0].textContent);
        // "Title | Site", "Title - Site": the longest part.
        const parts = documentTitle.split(/\s[|\-–—·:]\s/);
        return parts.reduce((longest, part) => (part.length > longest.length ? part : longest), "") || documentTitle;
    }

    function findByline(root) {
        bylineElement = null;
        const scopes = root ? [root, document] : [document];
        for (const scope of scopes) {
            const element = scope.querySelector(
                '.byline, [class*="byline"], [rel="author"], [itemprop="author"], .author'
            );
            const text = clean(element && element.textContent);
            if (text && text.length <= 100) {
                if (root && root.contains(element)) bylineElement = element;
                const author = meta("author", "article:author", "parsely-author");
                return author && !/^https?:/.test(author) ? author : text;
            }
        }
        const author = meta("author", "article:author", "parsely-author");
        return author && !/^https?:/.test(author) ? author : null;
    }

    function findDate(root) {
        const published = meta("article:published_time", "datePublished", "date", "dc.date");
        if (published) return published;
        const time = (root && root.querySelector("time[datetime]")) || document.querySelector("article time[datetime]");
        return time ? time.getAttribute("datetime") : null;
    }
    """#
}
