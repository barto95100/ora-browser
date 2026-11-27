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
    /// The channel of user scripts' worlds (`ExtensionUserScriptMessages`).
    static let userScriptHandlerName = "ombreUserScript"
    /// Native messaging to this "app" comes to Ombre (`ExtensionComplementPackage`).
    static let applicationIdentifier = "ombre.complement"

    /// The APIs added, by the permission that gives them.
    static let permissions: Set<String> = ["privacy", "offscreen", "userScripts", "idle", "notifications"]

    /// For pages: from the start of every extension page and frame.
    static var pageSource: String {
        source(isWorker: false, transport: #"""
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
        source(isWorker: true, transport: #"""
        (() => {
            const root = typeof browser === "object" ? browser : chrome;
            return root && root.runtime && root.runtime.sendNativeMessage
                ? message => root.runtime.sendNativeMessage("\#(applicationIdentifier)", message)
                : null;
        })()
        """#)
    }

    private static func source(isWorker: Bool, transport: String) -> String {
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

        const isWorker = \#(isWorker);

        """# + eventsPart + privacyPart + offscreenPart + userScriptsPart + idlePart + notificationsPart
            + permissionsPart + #"""
            })();
            """#
    }

    /// Events from Ombre (`ExtensionEvents`): one call waits while something
    /// listens in this context, answered when an event comes.
    private static let eventsPart = #"""
        const routes = {};
        const client = typeof crypto === "object" && typeof crypto.randomUUID === "function"
            ? crypto.randomUUID() : String(Math.random()).slice(2) + String(Date.now());
        let polling = false;
        function poll() {
            if (polling) return;
            polling = true;
            const loop = () => call("events", "next", { client: client }).then(list => {
                const items = Array.isArray(list) ? list : [];
                for (const item of items) {
                    const target = item && routes[item.name];
                    if (target) target.dispatch(...(Array.isArray(item.args) ? item.args : []));
                }
                // Nothing: only when Ombre ended the call; not again at once.
                if (items.length) loop(); else setTimeout(loop, 1000);
            }, () => setTimeout(loop, 5000));
            loop();
        }
        // An event of an added API: its first listener starts listening here.
        function ombreEvent(name, onListen) {
            const target = event();
            const add = target.addListener;
            target.addListener = listener => {
                add(listener);
                if (onListen) onListen();
                poll();
            };
            routes[name] = target;
            return target;
        }

    """#

    /// `chrome.idle` (`ExtensionIdle`).
    private static let idlePart = #"""
        if (declared.has("idle")) {
            let watched = false;
            install("idle", {
                IdleState: { ACTIVE: "active", IDLE: "idle", LOCKED: "locked" },
                queryState: (detectionIntervalInSeconds, callback) => either(call("idle", "queryState",
                    { detectionIntervalInSeconds: detectionIntervalInSeconds }), callback),
                setDetectionInterval: intervalInSeconds => {
                    call("idle", "setDetectionInterval", { intervalInSeconds: intervalInSeconds }).catch(() => {});
                },
                onStateChanged: ombreEvent("idle.onStateChanged", () => {
                    if (watched) return;
                    watched = true;
                    call("idle", "watch").catch(() => { watched = false; });
                })
            });
        }

    """#

    /// `chrome.notifications` (`ExtensionNotifications`): its pictures are
    /// read here, from the package (or where they are), and given to Ombre.
    private static let notificationsPart = #"""
        if (declared.has("notifications")) {
            const picture = url => {
                if (typeof url !== "string" || !url) return Promise.resolve(null);
                return fetch(/^[a-z][a-z0-9+.-]*:/i.test(url) ? url : root.runtime.getURL(url))
                    .then(response => response.ok ? response.blob() : null)
                    .then(blob => !blob || blob.size > 5242880 ? null : blob.arrayBuffer().then(buffer => {
                        const bytes = new Uint8Array(buffer);
                        let text = "";
                        for (let i = 0; i < bytes.length; i += 32768) {
                            text += String.fromCharCode.apply(null, bytes.subarray(i, i + 32768));
                        }
                        return { data: btoa(text), type: blob.type };
                    }))
                    .catch(() => null);
            };
            const withPictures = options => {
                const copy = Object.assign({}, options || {});
                return Promise.all([picture(copy.iconUrl), copy.type === "image" ? picture(copy.imageUrl) : null])
                    .then(([icon, image]) => {
                        if (icon) { copy.iconData = icon.data; copy.iconType = icon.type; }
                        if (image) { copy.imageData = image.data; copy.imageType = image.type; }
                        return copy;
                    });
            };
            const id = value => value === undefined || value === null ? null : String(value);
            install("notifications", {
                TemplateType: { BASIC: "basic", IMAGE: "image", LIST: "list", PROGRESS: "progress" },
                PermissionLevel: { GRANTED: "granted", DENIED: "denied" },
                create: (...values) => {
                    const callback = typeof values[values.length - 1] === "function" ? values.pop() : undefined;
                    const [notificationId, options] = values.length > 1 ? values : [undefined, values[0]];
                    return either(withPictures(options).then(given => call("notifications", "create",
                        { notificationId: id(notificationId), options: given })), callback);
                },
                update: (notificationId, options, callback) => either(withPictures(options).then(given =>
                    call("notifications", "update", { notificationId: id(notificationId), options: given })), callback),
                clear: (notificationId, callback) =>
                    either(call("notifications", "clear", { notificationId: id(notificationId) }), callback),
                getAll: callback => either(call("notifications", "getAll"), callback),
                getPermissionLevel: callback => either(call("notifications", "getPermissionLevel"), callback),
                onClicked: ombreEvent("notifications.onClicked"),
                onButtonClicked: ombreEvent("notifications.onButtonClicked"),
                onClosed: ombreEvent("notifications.onClosed"),
                onPermissionLevelChanged: event(),
                onShowSettings: event()
            });
        }

    """#

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

    /// `chrome.userScripts` (`ExtensionUserScripts`) and, in the service
    /// worker, `runtime.onUserScriptMessage` (`ExtensionUserScriptMessages`).
    private static let userScriptsPart = #"""
        // Only once the user allowed it ("Allow User Scripts"): otherwise
        // undefined, as in Chrome, for the extension to explain what to do.
        if (declared.has("userScripts") && manifest.\#(ExtensionComplementPackage.userScriptsAllowedKey) === true) {
            // A file's code is read here, from the package: Ombre gets the code.
            const withCode = scripts => Promise.all((Array.isArray(scripts) ? scripts : []).map(script => {
                if (!script || !Array.isArray(script.js)) return script;
                return Promise.all(script.js.map(source => {
                    if (!source || typeof source !== "object") return source;
                    const hasFile = source.file !== undefined, hasCode = source.code !== undefined;
                    if (hasFile === hasCode) {
                        throw new Error(`User script with ID '${script.id}' must specify exactly one of `
                            + "'code' or 'file'.");
                    }
                    if (!hasFile) return source;
                    return fetch(root.runtime.getURL(String(source.file))).then(response => {
                        if (!response.ok) throw new Error(`Could not load file: '${source.file}'.`);
                        return response.text();
                    }).then(code => ({ file: String(source.file), code: code }));
                })).then(js => Object.assign({}, script, { js: js }));
            }));
            const done = () => undefined;
            install("userScripts", {
                ExecutionWorld: { MAIN: "MAIN", USER_SCRIPT: "USER_SCRIPT" },
                register: (scripts, callback) => either(Promise.resolve().then(() => withCode(scripts))
                    .then(list => call("userScripts", "register", { scripts: list })).then(done), callback),
                update: (scripts, callback) => either(Promise.resolve().then(() => withCode(scripts))
                    .then(list => call("userScripts", "update", { scripts: list })).then(done), callback),
                unregister: (filter, callback) => {
                    if (typeof filter === "function") { callback = filter; filter = undefined; }
                    return either(call("userScripts", "unregister", { filter: filter || null }).then(done), callback);
                },
                getScripts: (filter, callback) => {
                    if (typeof filter === "function") { callback = filter; filter = undefined; }
                    return either(call("userScripts", "getScripts", { filter: filter || null }), callback);
                },
                configureWorld: (properties, callback) =>
                    either(call("userScripts", "configureWorld", { properties: properties || {} })
                        .then(done), callback),
                resetWorldConfiguration: (worldId, callback) => {
                    if (typeof worldId === "function") { callback = worldId; worldId = undefined; }
                    return either(call("userScripts", "resetWorldConfiguration", { worldId: worldId || null })
                        .then(done), callback);
                },
                getWorldConfigurations: callback => either(call("userScripts", "getWorldConfigurations"), callback)
            });
            const onMessage = event(), onConnect = event();
            const listeners = new Set();
            // Ombre's messages to the worker: a native port to its channel,
            // opened only once the worker listens (it may sleep otherwise:
            // Ombre wakes it when a message comes).
            let port = null;
            const listen = () => {
                if (port || !isWorker || typeof root.runtime.connectNative !== "function") return;
                port = root.runtime.connectNative(\#(applicationIdentifierLiteral));
                // Closed by Ombre (or the worker stops): not opened again at
                // once, which could loop; the next listener, or a wake, does.
                port.onDisconnect.addListener(() => { port = null; });
                port.onMessage.addListener(item => deliver(item, port));
            };
            const add = onMessage.addListener, remove = onMessage.removeListener;
            onMessage.addListener = listener => { listeners.add(listener); add(listener); listen(); };
            onMessage.removeListener = listener => { listeners.delete(listener); remove(listener); };
            for (const namespace of new Set([globalThis.browser, globalThis.chrome])) {
                if (!namespace || !namespace.runtime) continue;
                for (const [name, value] of [["onUserScriptMessage", onMessage], ["onUserScriptConnect", onConnect]]) {
                    if (namespace.runtime[name] !== undefined) continue;
                    const property = { value: value, enumerable: true, configurable: true };
                    try { Object.defineProperty(namespace.runtime, name, property); }
                    catch (e) {}
                }
            }
            // Its tab, as the tabs API sees it (Ombre gives its address).
            const tabOf = url => root.tabs && typeof root.tabs.query === "function" && url
                ? Promise.resolve(root.tabs.query({})).then(tabs =>
                    (tabs || []).filter(tab => tab.url === url).sort((a, b) => b.active - a.active)[0])
                    .catch(() => undefined)
                : Promise.resolve(undefined);
            const deliver = (item, from) => {
                if (!item || item.kind !== "message") return;
                const reply = value => from.postMessage(Object.assign({ kind: "reply", id: item.id }, value));
                if (!listeners.size) {
                    return reply({ error: "Could not establish connection. Receiving end does not exist." });
                }
                const sender = Object.assign({}, item.sender || {});
                (sender.frameId === 0 ? tabOf(sender.url) : Promise.resolve(undefined)).then(tab => {
                    if (tab) sender.tab = tab;
                    let answered = false, later = false;
                    const respond = value => { if (!answered) { answered = true; reply({ value: value }); } };
                    for (const listener of Array.from(listeners)) {
                        try {
                            const result = listener(item.message, sender, respond);
                            if (result === true) later = true;
                            else if (result && typeof result.then === "function") {
                                later = true;
                                result.then(respond, error => {
                                    if (answered) return;
                                    answered = true;
                                    reply({ error: String(error && error.message || error) });
                                });
                            }
                        } catch (e) {}
                    }
                    if (!later) respond(undefined);
                });
            };
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

    private static var applicationIdentifierLiteral: String {
        "\"\(applicationIdentifier)\"" // not shown
    }

    private static var permissionsLiteral: String {
        "[" + permissions.sorted().map { "\"\($0)\"" }.joined(separator: ", ") + "]" // not shown
    }
}
