import AppKit
import Foundation

/// The reader's page: the article in a column, in the chosen theme, size
/// and width. Shown with JavaScript off and a policy that only lets images
/// load: nothing of it can run.
enum ReaderDocument {
    struct Style: Equatable {
        let theme: ReaderSettings.Theme
        let width: ReaderSettings.Width
        let font: ReaderSettings.Font
        let size: Int
    }

    /// Nothing but images and the inline style: no script, frame, form,
    /// font or connection, whatever the article holds.
    static let contentSecurityPolicy =
        "default-src 'none'; img-src http: https: data:; style-src 'unsafe-inline'; form-action 'none'" // not shown

    static func html(for article: ReaderArticle, style: Style) -> String {
        let language = article.language.map { " lang=\"\(escaped($0))\"" } ?? "" // not shown
        let direction = article.isRightToLeft ? " dir=\"rtl\"" : "" // not shown
        return """
        <!doctype html>
        <html\(language)\(direction) \(attributes(for: style))>
        <head>
        <meta charset="utf-8">
        <meta http-equiv="Content-Security-Policy" content="\(contentSecurityPolicy)">
        <meta name="referrer" content="strict-origin-when-cross-origin">
        <title>\(escaped(article.title))</title>
        <style>\(css)</style>
        </head>
        <body>
        <article>
        <header>
        <p class="site">\(escaped(article.site))</p>
        <h1>\(escaped(article.title))</h1>
        <p class="details">\(escaped(article.details))</p>
        </header>
        <div class="content">\(article.html)</div>
        </article>
        </body>
        </html>
        """
    }

    /// The `<html>` element's attributes for a style.
    static func attributes(for style: Style) -> String {
        "data-theme=\"\(style.theme.rawValue)\" data-font=\"\(style.font.rawValue)\" " // not shown
            + "style=\"--size: \(style.size)px; --width: \(style.width.characters)ch\"" // not shown
    }

    /// Applies a style to the shown document (the app's script: the
    /// document's own can't run), keeping where the reader is.
    static func applyScript(for style: Style) -> String {
        """
        {
        const root = document.documentElement;
        const scroller = document.scrollingElement;
        const fraction = scroller.scrollHeight > 0 ? scroller.scrollTop / scroller.scrollHeight : 0;
        root.dataset.theme = "\(style.theme.rawValue)";
        root.dataset.font = "\(style.font.rawValue)";
        root.style.setProperty("--size", "\(style.size)px");
        root.style.setProperty("--width", "\(style.width.characters)ch");
        scroller.scrollTop = fraction * scroller.scrollHeight;
        }
        """
    }

    /// The theme's background, for the view behind the page (no flash).
    static func background(for theme: ReaderSettings.Theme, isDark: Bool) -> NSColor {
        switch theme {
        case .light: NSColor(srgbRed: 1, green: 1, blue: 1, alpha: 1)
        case .sepia: NSColor(srgbRed: 0.973, green: 0.945, blue: 0.890, alpha: 1)
        case .dark: NSColor(srgbRed: 0.118, green: 0.118, blue: 0.125, alpha: 1)
        case .automatic: background(for: isDark ? .dark : .light, isDark: isDark)
        }
    }

    static func escaped(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&#39;")
    }

    private static let css = """
    :root {
        --background: #ffffff; --text: #1d1d1f; --muted: #6e6e73; --link: #0a64d8; --rule: #d2d2d7;
        --code: #f2f2f4;
        color-scheme: light;
    }
    :root[data-theme="sepia"] {
        --background: #f8f1e3; --text: #4b3a26; --muted: #8a7559; --link: #8a4b10; --rule: #e2d4b8;
        --code: #efe5d1;
    }
    :root[data-theme="dark"] {
        --background: #1e1e20; --text: #dcdcdf; --muted: #9a9aa0; --link: #6aa8ff; --rule: #3a3a3e;
        --code: #2a2a2e;
        color-scheme: dark;
    }
    @media (prefers-color-scheme: dark) {
        :root[data-theme="automatic"] {
            --background: #1e1e20; --text: #dcdcdf; --muted: #9a9aa0; --link: #6aa8ff; --rule: #3a3a3e;
            --code: #2a2a2e;
            color-scheme: dark;
        }
    }
    html { background: var(--background); }
    body {
        margin: 0; padding: 48px 24px 96px; color: var(--text); background: var(--background);
        font: var(--size)/1.6 -apple-system, system-ui, sans-serif;
        -webkit-font-smoothing: antialiased; text-rendering: optimizeLegibility;
        overflow-wrap: break-word; hyphens: auto;
    }
    :root[data-font="serif"] body { font-family: "New York", ui-serif, Georgia, serif; }
    article { max-width: var(--width); margin: 0 auto; }
    header { margin-bottom: 2em; }
    header .site { margin: 0 0 0.4em; color: var(--muted); font-size: 0.8em; text-transform: uppercase;
        letter-spacing: 0.04em; }
    header h1 { margin: 0 0 0.4em; font-size: 1.9em; line-height: 1.2; }
    header .details { margin: 0; color: var(--muted); font-size: 0.85em; }
    h2, h3, h4, h5, h6 { line-height: 1.3; margin: 1.6em 0 0.6em; }
    h2 { font-size: 1.4em; } h3 { font-size: 1.2em; } h4, h5, h6 { font-size: 1em; }
    p, ul, ol, dl, blockquote, pre, table, figure { margin: 0 0 1.1em; }
    a { color: var(--link); text-decoration: none; }
    a:hover { text-decoration: underline; }
    img { display: block; max-width: 100%; height: auto; margin: 1.2em auto; border-radius: 4px; }
    figure { margin-left: 0; margin-right: 0; }
    figcaption, caption { color: var(--muted); font-size: 0.85em; text-align: center; }
    blockquote { margin-left: 0; padding-left: 1em; border-left: 3px solid var(--rule); color: var(--muted); }
    pre, code { font: 0.85em/1.5 ui-monospace, "SF Mono", Menlo, monospace; background: var(--code);
        border-radius: 4px; }
    code { padding: 0.1em 0.3em; }
    pre { padding: 0.8em 1em; overflow-x: auto; white-space: pre; hyphens: none; }
    table { border-collapse: collapse; width: 100%; font-size: 0.9em; display: block; overflow-x: auto; }
    th, td { border: 1px solid var(--rule); padding: 0.4em 0.6em; text-align: start; vertical-align: top; }
    hr { border: 0; border-top: 1px solid var(--rule); margin: 2em 0; }
    ::selection { background: color-mix(in srgb, var(--link) 30%, transparent); }
    """
}
