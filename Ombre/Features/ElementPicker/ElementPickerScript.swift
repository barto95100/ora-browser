import WebKit

/// The element picker's part in the page (see `ElementPickerOverlay`): it
/// finds the block under a point, widens or narrows it, and gives a CSS
/// selector for it. In its own world: the page can't see or call it, and it
/// adds nothing to the page's document while the user looks (the highlight
/// is drawn by the app, over the page).
///
/// Selectors must still find the element on the next visits: no class or
/// identifier a framework generated (CSS modules, styled-components,
/// Emotion, counters like `ember123` or React's `:r1:`), and no state class
/// (`active`, `open`…). A stable identifier first, then stable attributes
/// (`data-testid`, `aria-label`…) and classes, then the structure.
enum ElementPickerScript {
    @MainActor static let world = WKContentWorld.world(name: "picker")

    /// Installs `window.__ombrePicker` in the picker's world (once per document).
    static let source = #"""
    (() => {
    if (window.__ombrePicker) return;

    const stateClass = new RegExp("^(is-|has-)?(" + [
        "active", "hover", "hovered", "focus", "focused", "focus-visible", "selected", "open", "opened",
        "show", "shown", "showing", "visible", "hidden", "collapsed", "expanded", "current", "disabled",
        "loading", "loaded", "animate", "animated", "animating", "in", "fade", "enter", "leave", "sticky",
        "stuck", "scrolled"
    ].join("|") + ")$", "i");
    const generatedPrefix = /^(css|sc|jsx|svelte|astro|emotion|styled|tw|ng-tns|ng-star|_ngcontent|_nghost)-/i;

    // A token (class or identifier) a person wrote, not a build tool or a counter.
    function isStableToken(token, isIdentifier) {
        if (!token || token.length > 48) return false;
        if (stateClass.test(token) || generatedPrefix.test(token)) return false;
        if (/^[^A-Za-z]/.test(token)) return false;           // ":r1:", "123", "_a1"
        if (/\d{3,}/.test(token)) return false;               // "ember123", "post-12345"
        if (/[0-9a-f]{5,}/i.test(token) && /\d/.test(token)) return false;  // hashes
        if (/(__|_|-)[A-Za-z0-9]{5,}$/.test(token)) {
            const tail = token.match(/(?:__|_|-)([A-Za-z0-9]{5,})$/)[1];
            const mixed = /\d/.test(tail) || (/[a-z]/.test(tail) && /[A-Z]/.test(tail) && !/^[A-Z][a-z]+$/.test(tail));
            if (mixed) return false;                          // "Header_title__aB3dE"
        }
        if (!/[-_]/.test(token) && token.length >= 5 && token.length <= 10) {
            const switches = (token.match(/[a-z][A-Z]|[A-Z][a-z]|[A-Za-z]\d|\d[A-Za-z]/g) || []).length;
            if (switches >= 4) return false;                  // "kQzPfE", "a1B2c"
        }
        // Identifiers: no number at all between separators ("select-2-input").
        if (isIdentifier && /(^|[-_:.])\d+([-_:.]|$)/.test(token)) return false;
        return true;
    }

    // Attributes set for tests and tools: meant to stay.
    const testAttributes = [
        "data-testid", "data-test-id", "data-test", "data-qa", "data-cy",
        "data-component", "data-module", "data-viz-panel-key", "data-panelid"
    ];

    function isStableValue(value) {
        return !!value && value.length <= 80 && !/\d{5,}/.test(value) && !/[0-9a-f]{8,}/i.test(value);
    }

    function quoted(value) {
        return '"' + value.replace(/\\/g, "\\\\").replace(/"/g, '\\"').replace(/\n/g, "\\a ") + '"';
    }

    function isUnique(selector, element) {
        try {
            const found = document.querySelectorAll(selector);
            return found.length === 1 && found[0] === element;
        } catch (e) {
            return false;
        }
    }

    // One step of the path: the element alone, told apart from its siblings.
    function segment(element) {
        const tag = CSS.escape(element.localName);
        if (element === document.body) return { text: "body", anchor: true };
        const id = element.getAttribute("id");
        if (id && isStableToken(id, true) && isUnique("#" + CSS.escape(id), element)) {
            return { text: "#" + CSS.escape(id), anchor: true };
        }
        let text = tag;
        const attribute = testAttributes.find(name => isStableValue(element.getAttribute(name)));
        const classes = Array.from(element.classList).filter(c => isStableToken(c, false)).slice(0, 2);
        // Words (aria-label) change with the language or the content: after the classes.
        const words = ["aria-label", "itemprop", "role"]
            .find(name => isStableValue(element.getAttribute(name)) && !/\d/.test(element.getAttribute(name)));
        if (attribute) {
            text += "[" + attribute + "=" + quoted(element.getAttribute(attribute)) + "]";
        } else if (classes.length) {
            text += classes.map(c => "." + CSS.escape(c)).join("");
        } else if (words) {
            text += "[" + words + "=" + quoted(element.getAttribute(words)) + "]";
        }
        const parent = element.parentElement;
        if (parent) {
            const alike = Array.from(parent.children).filter(child => {
                try { return child.matches(text); } catch (e) { return false; }
            });
            if (alike.length > 1) {
                const sameTag = Array.from(parent.children).filter(child => child.localName === element.localName);
                text += ":nth-of-type(" + (sameTag.indexOf(element) + 1) + ")";
            }
        }
        return { text: text, anchor: false };
    }

    function selectorFor(element) {
        const parts = [];
        let node = element;
        while (node && node.nodeType === 1 && node !== document.documentElement) {
            const step = segment(node);
            parts.unshift(step.text);
            const selector = parts.join(" > ");
            if (isUnique(selector, element)) return selector;
            node = node.parentElement;
        }
        return parts.join(" > ");
    }

    function label(element) {
        let text = element.localName;
        const id = element.getAttribute("id");
        if (id && isStableToken(id, true)) {
            text += "#" + id;
        } else {
            const name = Array.from(element.classList).find(c => isStableToken(c, false));
            if (name) text += "." + name;
        }
        return text;
    }

    // What a person would call it, saved when it is hidden (it isn't shown
    // afterwards): its own name (label, title, heading, image text), else
    // its kind. Never its text: it can be about the user ("Hello Jane").
    function words(text, limit) {
        const clean = (text || "").replace(/\s+/g, " ").trim();
        if (!clean) return null;
        return clean.length > limit ? clean.slice(0, limit - 1).trimEnd() + "…" : clean;
    }

    function ownName(element) {
        const named = words(element.getAttribute("aria-label"), 60) || words(element.getAttribute("title"), 60);
        if (named) return named;
        const labelledBy = (element.getAttribute("aria-labelledby") || "").split(/\s+/)
            .map(id => id && document.getElementById(id)).filter(Boolean)
            .map(node => node.textContent).join(" ");
        if (words(labelledBy, 60)) return words(labelledBy, 60);
        const heading = element.querySelector("h1, h2, h3, h4, h5, h6");
        if (heading && words(heading.textContent, 60)) return words(heading.textContent, 60);
        const image = element.localName === "img" ? element : null;
        if (image && words(image.getAttribute("alt"), 60)) return words(image.getAttribute("alt"), 60);
        return null;
    }

    const roleKinds = {
        navigation: "navigation", complementary: "sidebar", banner: "banner", contentinfo: "footer",
        dialog: "dialog", alertdialog: "dialog", search: "search", form: "form", img: "image",
        main: "main", article: "article", region: "section", list: "list", table: "table",
        menu: "menu", menubar: "menu", toolbar: "toolbar", button: "button", alert: "notice"
    };
    const tagKinds = {
        nav: "navigation", aside: "sidebar", header: "banner", footer: "footer", dialog: "dialog",
        form: "form", img: "image", picture: "image", figure: "image", svg: "image", canvas: "image",
        video: "video", audio: "audio", iframe: "embed", embed: "embed", object: "embed", main: "main",
        article: "article", section: "section", ul: "list", ol: "list", table: "table", button: "button"
    };

    function kind(element) {
        const role = (element.getAttribute("role") || "").toLowerCase();
        return roleKinds[role] || tagKinds[element.localName] || null;
    }

    function isBlock(element) {
        const display = getComputedStyle(element).display;
        const box = element.getBoundingClientRect();
        return display !== "inline" && display !== "contents" && box.width >= 8 && box.height >= 8;
    }

    let chain = [];
    let level = 0;
    const hidden = new Set();

    // From the element under the point up to the body's child.
    function start(element) {
        chain = [];
        for (let node = element; node && node !== document.body && node !== document.documentElement;
             node = node.parentElement) {
            chain.push(node);
        }
        level = Math.max(0, chain.findIndex(isBlock));
        return current();
    }

    function current() {
        const element = chain[level];
        if (!element || !element.isConnected) return null;
        const box = element.getBoundingClientRect();
        return {
            x: box.left, y: box.top, width: box.width, height: box.height,
            label: label(element), canWiden: level < chain.length - 1, canNarrow: level > 0
        };
    }

    window.__ombrePicker = {
        isStableToken: isStableToken,
        selectorFor: selectorFor,
        ownName: ownName,
        kind: kind,
        start: start,
        hit(x, y) {
            const element = document.elementsFromPoint(x, y)
                .find(node => node !== document.body && node !== document.documentElement);
            if (!element) { chain = []; return null; }
            if (chain[0] === element) return current();
            return start(element);
        },
        widen() { if (level < chain.length - 1) level += 1; return current(); },
        narrow() { if (level > 0) level -= 1; return current(); },
        // The chosen element: its selector, brought into view for a capture.
        choose() {
            const element = chain[level];
            if (!element || !element.isConnected) return null;
            return {
                selector: selectorFor(element), label: label(element),
                name: ownName(element), kind: kind(element)
            };
        },
        reveal() {
            const element = chain[level];
            if (!element || !element.isConnected) return null;
            element.scrollIntoView({ block: "nearest", inline: "nearest", behavior: "instant" });
            return current();
        },
        // Hidden at once on this page (the rule list does it from the next load).
        hide(selector) {
            let count = 0;
            try {
                document.querySelectorAll(selector).forEach(element => {
                    element.style.setProperty("display", "none", "important");
                    hidden.add(element);
                    count += 1;
                });
            } catch (e) {}
            return count;
        },
        stop() { chain = []; level = 0; }
    };
    })();
    """#
}
