import Foundation

/// The page's side of translation, in the app's world (the page can't see
/// or change it): reads the page's language and text, puts translated text
/// in place, and puts the original back.
enum PageTranslatorScript {
    static let userScript = BrowserUserScript(
        name: "ombre-translator",
        source: source,
        injectionTime: .atDocumentEnd,
        forMainFrameOnly: true
    )

    /// Text that isn't prose to translate: code, fields, scripts, or marked
    /// so by the page (`translate="no"`, the "notranslate" class).
    static let source = """
    (function () {
        if (window.__translator) return;
        const skipped = new Set(['SCRIPT', 'STYLE', 'NOSCRIPT', 'TEXTAREA', 'CODE', 'PRE', 'KBD', 'SAMP', 'svg']);
        const maximum = 3000;
        let nodes = [];
        let originals = [];
        // What each node shows once translated, to put back only those.
        let translatedValues = [];

        function isSkipped(element) {
            for (let node = element; node && node !== document.documentElement; node = node.parentElement) {
                if (skipped.has(node.tagName) || node.isContentEditable) return true;
                if (node.getAttribute('translate') === 'no' || node.classList.contains('notranslate')) return true;
            }
            return false;
        }

        function textNodes(limit, visit) {
            if (!document.body) return;
            const walker = document.createTreeWalker(document.body, NodeFilter.SHOW_TEXT);
            for (let node = walker.nextNode(); node && limit(); node = walker.nextNode()) {
                if (!/[\\p{L}]/u.test(node.nodeValue) || isSkipped(node.parentElement)) continue;
                visit(node);
            }
        }

        window.__translator = {
            /// The language the page declares, a sample of its text (read
            /// from the nodes, without laying the page out), and whether it
            /// is shown translated (a page back from the back/forward cache).
            info() {
                let sample = '';
                textNodes(() => sample.length < 2000, (node) => { sample += node.nodeValue.trim() + ' '; });
                return JSON.stringify({
                    lang: document.documentElement.lang || '',
                    sample: sample.slice(0, 2000),
                    translated: translatedValues.some((value) => value !== undefined)
                });
            },
            /// The page's text pieces to translate: those on screen first
            /// (shown translated within a second or two), then the others
            /// in the page's order.
            collect() {
                this.restore();
                const visible = [];
                const others = [];
                const height = window.innerHeight;
                textNodes(() => visible.length + others.length < maximum, (node) => {
                    const box = node.parentElement.getBoundingClientRect();
                    const onScreen = box.width > 0 && box.bottom > 0 && box.top < height;
                    (onScreen ? visible : others).push(node);
                });
                nodes = visible.concat(others);
                originals = nodes.map((node) => node.nodeValue);
                translatedValues = new Array(nodes.length);
                return JSON.stringify(originals.map((text) => text.trim()));
            },
            /// Translations by piece number; the spaces around each piece are
            /// kept, and a piece the page changed meanwhile is left alone.
            apply(json) {
                const translations = JSON.parse(json);
                for (const [key, translated] of Object.entries(translations)) {
                    const index = Number(key);
                    const node = nodes[index];
                    if (!node || typeof translated !== 'string' || !translated) continue;
                    const original = originals[index];
                    if (node.nodeValue !== original) continue;
                    const lead = original.match(/^\\s*/)[0];
                    const trail = original.match(/\\s*$/)[0];
                    node.nodeValue = lead + translated + trail;
                    translatedValues[index] = node.nodeValue;
                }
                return true;
            },
            /// The page as it was, where it still shows the translation.
            restore() {
                nodes.forEach((node, index) => {
                    if (translatedValues[index] !== undefined && node.nodeValue === translatedValues[index]) {
                        node.nodeValue = originals[index];
                    }
                });
                nodes = [];
                originals = [];
                translatedValues = [];
                return true;
            }
        };
    })();
    """
}
