import Foundation

/// APIs Chrome gives extensions and WebKit doesn't, added by Ombre: the
/// same script in an extension's pages (background page, popup, options,
/// offscreen document) and, for Ombre's copies, in its service worker.
///
/// It defines only what the extension's manifest asks for, as Chrome does
/// (`chrome.privacy` without the "privacy" permission is `undefined`), and
/// never replaces an API WebKit has. Every call goes to Ombre
/// (`ExtensionComplements`), which checks again what the extension asked
/// for: the script decides nothing.
enum ExtensionComplementScript {
    /// The channel from pages: a script message handler of the extensions'
    /// pages only (their configuration), answered by Ombre.
    static let handlerName = "ombreComplement"
    /// Native messaging to this "app" comes to Ombre (`ExtensionComplementPackage`).
    static let applicationIdentifier = "ombre.complement"

    /// The APIs added, by the permission that gives them.
    static let permissions: Set<String> = ["privacy", "offscreen"]

    /// For pages: from the start of every extension page and frame.
    static var pageSource: String {
        source(transport: #"""
        (() => {
            const handler = window.webkit && window.webkit.messageHandlers
                && window.webkit.messageHandlers.\#(handlerName);
            return handler ? message => handler.postMessage(message) : null;
        })()
        """#)
    }

    /// For a service worker (Ombre's copies only): through native messaging
    /// to Ombre's own channel, the only way out of a worker.
    static var workerSource: String {
        source(transport: #"""
        (() => {
            const root = typeof browser === "object" ? browser : chrome;
            return root && root.runtime && root.runtime.sendNativeMessage
                ? message => root.runtime.sendNativeMessage("\#(applicationIdentifier)", message)
                : null;
        })()
        """#)
    }

    private static func source(transport: String) -> String {
        #"""
        (() => {
        const root = typeof browser === "object" ? browser : (typeof chrome === "object" ? chrome : null);
        if (!root || !root.runtime || !root.runtime.id || root.runtime.__ombreComplement) return;
        const send = \#(transport);
        if (!send) return;
        try { Object.defineProperty(root.runtime, "__ombreComplement", { value: true }); } catch (e) {}

        const manifest = root.runtime.getManifest() || {};
        const declared = new Set([].concat(manifest.permissions || [], manifest.optional_permissions || [])
            .filter(name => typeof name === "string"));
        const ours = new Set(\#(permissionsLiteral));

        function call(api, method, details) {
            return Promise.resolve(send({ api: api, method: method, details: details === undefined ? null : details }))
                .then(reply => {
                    if (reply && typeof reply.error === "string") throw new Error(reply.error);
                    return reply ? reply.value : undefined;
                });
        }
        // Chrome's both forms: a promise, or a callback (given nothing on an error).
        function either(promise, callback) {
            if (typeof callback !== "function") return promise;
            promise.then(value => callback(value), () => callback(undefined));
            return undefined;
        }
        function event() {
            const listeners = new Set();
            return {
                addListener: listener => { listeners.add(listener); },
                removeListener: listener => { listeners.delete(listener); },
                hasListener: listener => listeners.has(listener),
                hasListeners: () => listeners.size > 0,
                dispatch: (...values) => listeners.forEach(listener => { try { listener(...values); } catch (e) {} })
            };
        }
        function install(name, value) {
            for (const namespace of new Set([globalThis.browser, globalThis.chrome])) {
                if (!namespace || namespace[name] !== undefined) continue;
                try { Object.defineProperty(namespace, name, { value: value, enumerable: true, configurable: true }); }
                catch (e) { try { namespace[name] = value; } catch (e2) {} }
            }
        }

        """# + privacyPart + offscreenPart + permissionsPart + #"""
        })();
        """#
    }

    /// `chrome.privacy`: Ombre's settings (`ExtensionPrivacy`).
    private static let privacyPart = #"""
        if (declared.has("privacy")) {
            const setting = path => {
                const onChange = event();
                return {
                    get: (details, callback) => either(call("privacy", "get", { setting: path, details: details || {} }), callback),
                    set: (details, callback) => either(call("privacy", "set", { setting: path, details: details || {} })
                        .then(() => call("privacy", "get", { setting: path, details: {} }))
                        .then(value => { onChange.dispatch(value); }), callback),
                    clear: (details, callback) => either(call("privacy", "clear", { setting: path, details: details || {} })
                        .then(() => undefined), callback),
                    onChange: onChange
                };
            };
            const tree = {
                network: ["networkPredictionEnabled", "webRTCIPHandlingPolicy"],
                services: ["alternateErrorPagesEnabled", "autofillEnabled", "autofillAddressEnabled",
                    "autofillCreditCardEnabled", "passwordSavingEnabled", "safeBrowsingEnabled",
                    "safeBrowsingExtendedReportingEnabled", "searchSuggestEnabled", "spellingServiceEnabled",
                    "translationServiceEnabled"],
                websites: ["doNotTrackEnabled", "hyperlinkAuditingEnabled", "protectedContentEnabled",
                    "referrersEnabled", "thirdPartyCookiesAllowed", "topicsEnabled", "fledgeEnabled",
                    "adMeasurementEnabled"]
            };
            const privacy = {};
            for (const group of Object.keys(tree)) {
                privacy[group] = {};
                for (const name of tree[group]) privacy[group][name] = setting(group + "." + name);
            }
            privacy.IPHandlingPolicy = {
                DEFAULT: "default", DEFAULT_PUBLIC_AND_PRIVATE_INTERFACES: "default_public_and_private_interfaces",
                DEFAULT_PUBLIC_INTERFACE_ONLY: "default_public_interface_only",
                DISABLE_NON_PROXIED_UDP: "disable_non_proxied_udp"
            };
            install("privacy", privacy);
        }

    """#

    /// `chrome.offscreen` (`OffscreenDocuments`).
    private static let offscreenPart = #"""
        if (declared.has("offscreen")) {
            const reasons = ["TESTING", "AUDIO_PLAYBACK", "IFRAME_SCRIPTING", "DOM_SCRAPING", "BLOBS",
                "DOM_PARSER", "USER_MEDIA", "DISPLAY_MEDIA", "WEB_RTC", "CLIPBOARD", "LOCAL_STORAGE", "WORKERS",
                "BATTERY_STATUS", "MATCH_MEDIA", "GEOLOCATION"];
            install("offscreen", {
                Reason: Object.fromEntries(reasons.map(reason => [reason, reason])),
                createDocument: (parameters, callback) =>
                    either(call("offscreen", "createDocument", parameters || {}).then(() => undefined), callback),
                closeDocument: callback => either(call("offscreen", "closeDocument").then(() => undefined), callback),
                hasDocument: callback => either(call("offscreen", "hasDocument"), callback)
            });
            // How Chrome's documentation finds the document: its contexts.
            if (typeof root.runtime.getContexts !== "function") {
                const getContexts = (filter, callback) => either(call("offscreen", "contexts", filter || {}), callback);
                for (const namespace of new Set([globalThis.browser, globalThis.chrome])) {
                    if (namespace && namespace.runtime && !namespace.runtime.getContexts) {
                        try { namespace.runtime.getContexts = getContexts; } catch (e) {}
                    }
                }
            }
        }

    """#

    /// `permissions.contains`, `request`, `remove` for the added APIs.
    private static let permissionsPart = #"""
        // The permissions of these APIs: WebKit doesn't know them. And what
        // Ombre added to its copy (native messaging, for its own channel)
        // isn't the extension's: never granted to it, as before.
        const permissions = root.permissions;
        const hidden = new Set(Array.isArray(manifest.ombre_added_permissions) ? manifest.ombre_added_permissions : []);
        if (permissions) {
            const split = value => {
                const names = (value && value.permissions) || [];
                return {
                    added: names.filter(name => ours.has(name)),
                    hidden: names.filter(name => hidden.has(name)),
                    rest: Object.assign({}, value || {},
                        { permissions: names.filter(name => !ours.has(name) && !hidden.has(name)) })
                };
            };
            const original = {
                contains: permissions.contains && permissions.contains.bind(permissions),
                request: permissions.request && permissions.request.bind(permissions),
                remove: permissions.remove && permissions.remove.bind(permissions),
                getAll: permissions.getAll && permissions.getAll.bind(permissions)
            };
            const wrapped = method => (value, callback) => {
                const parts = split(value);
                if (!parts.added.length && !parts.hidden.length) return original[method](value, callback);
                if (parts.hidden.length && method !== "remove") return either(Promise.resolve(false), callback);
                const hasRest = parts.rest.permissions.length || (parts.rest.origins || []).length;
                const theirs = () => hasRest ? Promise.resolve(original[method](parts.rest)) : Promise.resolve(true);
                const ombres = () => parts.added.length
                    ? call("permissions", method, { permissions: parts.added }) : Promise.resolve(true);
                // All or nothing, as Chrome: Ombre's only once the rest is granted.
                const result = method === "request"
                    ? theirs().then(granted => granted ? ombres() : false)
                    : Promise.all([theirs(), ombres()]).then(([a, b]) => a && b);
                return either(result.then(value => !!value), callback);
            };
            for (const method of ["contains", "request", "remove"]) {
                if (!original[method]) continue;
                try { permissions[method] = wrapped(method); } catch (e) {}
            }
            if (original.getAll) {
                try {
                    permissions.getAll = callback => either(Promise.resolve(original.getAll()).then(all => {
                        const names = ((all && all.permissions) || []).filter(name => !hidden.has(name));
                        return call("permissions", "granted", {}).then(granted =>
                            Object.assign({}, all, { permissions: names.concat(granted || []) }));
                    }), callback);
                } catch (e) {}
            }
        }

    """#

    private static var permissionsLiteral: String {
        "[" + permissions.sorted().map { "\"\($0)\"" }.joined(separator: ", ") + "]" // not shown
    }
}
