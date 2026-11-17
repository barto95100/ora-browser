import Foundation
import WebKit

/// What agents do in a web page once page actions are allowed: click an
/// element, fill in a field, run JavaScript. In the agents' own script world
/// (see `BrowserPage.agentWorld`): it sees the page's document, not the page's
/// variables nor the app's scripts. Selectors, values and code go as
/// arguments or as the function's body, never pasted into another script.
@MainActor
enum AgentPageActions {
    /// An action not answered by then is given up: with the user's question
    /// (100 s at most), within the 120 s osascript waits. The tests set their own.
    static var timeout: Duration = .seconds(15)
    /// A script's result is refused past that (in JSON characters).
    static let maxResultLength = 100_000

    /// A short description of the element the agent acted on. Never a
    /// field's value (a password, a hidden token): its label only.
    private static let describe = """
    const describe = (el) => {
        const isField = el instanceof HTMLInputElement || el instanceof HTMLTextAreaElement
            || el instanceof HTMLSelectElement;
        const label = el.getAttribute('aria-label') || el.getAttribute('placeholder') || el.getAttribute('name');
        const text = ((isField ? '' : el.innerText) || label || '').trim();
        return el.tagName.toLowerCase() + (el.id ? '#' + el.id : '')
            + (text ? ' "' + text.slice(0, 60) + '"' : '');
    };
    """ // not shown

    /// Clicks the first element `selector` matches.
    static let clickScript = describe + """
    let el;
    try { el = document.querySelector(selector); } catch (e) { return { error: 'selector' }; }
    if (!el) return { error: 'none' };
    if (el.matches(':disabled')) return { error: 'disabled' };
    el.scrollIntoView({ block: 'center', inline: 'center' });
    if (typeof el.focus === 'function') el.focus();
    if (typeof el.click === 'function') {
        el.click();
    } else {
        // An SVG icon inside a button, for one: no click() of its own.
        el.dispatchEvent(new MouseEvent('click', { bubbles: true, cancelable: true, view: window }));
    }
    return { element: describe(el) };
    """ // not shown

    /// Fills the first field `selector` matches with `value`, as typing
    /// would (input and change events: the page's own code sees it).
    /// Never a password field.
    static let fillScript = describe + """
    let el;
    try { el = document.querySelector(selector); } catch (e) { return { error: 'selector' }; }
    if (!el) return { error: 'none' };
    if (el instanceof HTMLInputElement && el.type.toLowerCase() === 'password') return { error: 'password' };
    const unfillable = ['button', 'checkbox', 'file', 'hidden', 'image', 'radio', 'reset', 'submit'];
    if (el instanceof HTMLInputElement && unfillable.includes(el.type.toLowerCase())) return { error: 'field' };
    // Disabled itself or by its fieldset.
    if (el.matches(':disabled') || el.readOnly) return { error: 'readonly' };
    if (el instanceof HTMLSelectElement && !Array.from(el.options).some((o) => o.value === value)) {
        return { error: 'option' };
    }
    el.scrollIntoView({ block: 'center', inline: 'center' });
    if (typeof el.focus === 'function') el.focus();
    if (el instanceof HTMLInputElement || el instanceof HTMLTextAreaElement) {
        // The element's own setter: a page's framework watching `value` sees the change.
        const proto = el instanceof HTMLInputElement ? HTMLInputElement.prototype : HTMLTextAreaElement.prototype;
        const setter = Object.getOwnPropertyDescriptor(proto, 'value').set;
        const before = el.value;
        setter.call(el, value);
        // A number, a date or a color field drops text it can't take: put
        // back as it was (text fields only drop newlines).
        const strict = ['number', 'date', 'time', 'datetime-local', 'month', 'week', 'color', 'range'];
        if (el instanceof HTMLInputElement && strict.includes(el.type.toLowerCase()) && el.value !== value) {
            setter.call(el, before);
            return { error: 'refused' };
        }
    } else if (el instanceof HTMLSelectElement) {
        el.value = value;
    } else if (el.isContentEditable) {
        el.textContent = value;
    } else {
        return { error: 'field' };
    }
    el.dispatchEvent(new Event('input', { bubbles: true }));
    el.dispatchEvent(new Event('change', { bubbles: true }));
    return { element: describe(el) };
    """ // not shown

    static func click(_ selector: String, on page: BrowserPage) async -> Result<String, AgentError> {
        await element(clickScript, ["selector": selector], on: page)
    }

    static func fill(_ selector: String, with value: String, on page: BrowserPage) async -> Result<String, AgentError> {
        await element(fillScript, ["selector": selector, "value": value], on: page)
    }

    /// The agent's code, as an async function's body, its result made JSON
    /// in the page: a huge one never comes to the app.
    static func runScript(_ code: String) -> String {
        """
        let result;
        try {
            result = await (async () => {
        \(code)
            })();
        } catch (error) {
            // What the code threw, apart from WebKit's own errors.
            let thrown;
            try { thrown = String(error); } catch (e) { thrown = 'A value that has no text.'; }
            return { thrown: thrown.slice(0, limit) };
        }
        const text = JSON.stringify(result === undefined ? null : result);
        if (text === undefined) return { unsupported: true };
        if (text.length > limit) return { tooLong: true };
        return { json: text };
        """ // not shown
    }

    /// Runs the agent's `code` (an async function's body: `return` gives its
    /// result, `await` works); its result as JSON text ("null" for none).
    static func run(_ code: String, on page: BrowserPage) async -> Result<String, AgentError> {
        await call(runScript(code), ["limit": maxResultLength], on: page).flatMap { reply in
            let reply = value(of: reply) as? [String: Any]
            if let json = reply?["json"] as? String { return .success(json) }
            if let thrown = reply?["thrown"] as? String { return .failure(.scriptFailed(thrown)) }
            return .failure(reply?["tooLong"] != nil ? .resultTooLong : .unsupportedResult)
        }
    }

    /// The element's description once acted on, or why it couldn't be.
    private static func element(
        _ script: String,
        _ arguments: [String: Any],
        on page: BrowserPage
    ) async -> Result<String, AgentError> {
        switch await call(script, arguments, on: page) {
        case let .failure(error):
            return .failure(error)
        case let .success(json):
            let reply = value(of: json) as? [String: Any]
            if let element = reply?["element"] as? String { return .success(element) }
            let error: AgentError = switch reply?["error"] as? String {
            case "selector": .badSelector
            case "none": .noElement
            case "password": .passwordField
            case "readonly": .readOnlyField
            case "disabled": .disabledElement
            case "option": .noOption
            case "refused": .valueRefused
            default: .notFillable
            }
            return .failure(error)
        }
    }

    /// `body` run in the agents' world, answered once: by the page, or by
    /// the timeout. What it returns, as JSON text.
    private static func call(
        _ body: String,
        _ arguments: [String: Any],
        on page: BrowserPage
    ) async -> Result<String, AgentError> {
        await withCheckedContinuation { continuation in
            let answer = Once(continuation)
            let deadline = Task { @MainActor in
                try? await Task.sleep(for: timeout)
                guard !Task.isCancelled else { return }
                answer.resume(.failure(.timedOut))
            }
            page.callAgentJavaScript(body, arguments: arguments) { result in
                deadline.cancel()
                answer.resume(
                    result.mapError(failure)
                        .flatMap { json($0 ?? NSNull()).map { .success($0) } ?? .failure(.unsupportedResult) }
                )
            }
        }
    }

    /// What WebKit says when it stops waiting for a script's promise: freed
    /// by the page (nothing referenced it) or gone with its document.
    static let droppedPromiseMessage = "Completion handler for function call is no longer reachable"

    /// Why the call failed.
    static func failure(_ error: Error) -> AgentError {
        let nsError = error as NSError
        if nsError.domain == WKError.errorDomain,
           nsError.code == WKError.Code.javaScriptExceptionOccurred.rawValue,
           nsError.userInfo["WKJavaScriptExceptionMessage"] as? String == droppedPromiseMessage
        {
            return .promiseDropped
        }
        return .scriptFailed(scriptError(error))
    }

    /// What the script threw, for the agent (never logged).
    private static func scriptError(_ error: Error) -> String {
        let info = (error as NSError).userInfo
        // (Its line number isn't kept: WebKit loses it across the awaits.)
        return info["WKJavaScriptExceptionMessage"] as? String ?? PageLog.describe(error)
    }

    /// `value` as JSON text, if it is JSON (what WebKit gives back: strings,
    /// numbers, booleans, arrays, objects, null).
    static func json(_ value: Any) -> String? {
        guard JSONSerialization.isValidJSONObject([value]),
              let data = try? JSONSerialization.data(
                  withJSONObject: value,
                  options: [.fragmentsAllowed, .sortedKeys, .withoutEscapingSlashes]
              )
        else { return nil }
        return String(bytes: data, encoding: .utf8)
    }

    /// The value of JSON text made by `json`.
    static func value(of json: String) -> Any? {
        try? JSONSerialization.jsonObject(with: Data(json.utf8), options: .fragmentsAllowed)
    }

    /// Resumes its continuation once.
    private final class Once {
        private var continuation: CheckedContinuation<Result<String, AgentError>, Never>?

        init(_ continuation: CheckedContinuation<Result<String, AgentError>, Never>) {
            self.continuation = continuation
        }

        func resume(_ result: Result<String, AgentError>) {
            continuation?.resume(returning: result)
            continuation = nil
        }
    }
}
