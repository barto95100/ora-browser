import Foundation

/// The standard `Notification` API, which WebKit leaves out of apps, backed by
/// `WebNotificationBridge`. Secure pages only, like in every browser.
///
/// It must run in the page's world (it gives the page an API), so it leaves
/// nothing else there: its helpers are private to it, and it reaches the app
/// through `relay`, in the app's world, with events named after `channel`, a
/// secret of the page. No handler of the app is in the page's world: Safari's
/// pages have no `window.webkit`, Ombre's neither.
enum WebNotificationScript {
    /// The permission of the site a page is about to show, given by the
    /// script so `Notification.permission` is right from the start (MOT-18).
    /// Only a saved choice ("granted", "denied"), for a secure site.
    struct InitialState: Equatable {
        /// As the page's `location.origin` says it.
        let origin: String
        let permission: String

        init?(url: URL, permission: String) {
            guard permission != "default", url.scheme?.lowercased() == "https",
                  let host = url.host(percentEncoded: true)?.lowercased(), !host.isEmpty
            else { return nil }
            let shownHost = host.contains(":") ? "[\(host)]" : host
            let port = url.port.flatMap { $0 == 443 ? nil : ":\($0)" } ?? ""
            origin = "https://\(shownHost)\(port)"
            self.permission = permission
        }

        /// As JSON, for the script.
        var json: String {
            let object = ["origin": origin, "permission": permission]
            guard let data = try? JSONSerialization.data(withJSONObject: object, options: .sortedKeys),
                  let json = String(data: data, encoding: .utf8)
            else { return "null" }
            return json
        }
    }

    static func source(channel: String, initial: InitialState? = nil) -> String {
        "(() => {\n  const channel = '\(channel)';\n  const initial = \(initial?.json ?? "null");\n"
            + api + clicks(channel: channel) + permissions
    }

    /// In the app's world: passes the API's messages to the app's handler
    /// and its answers back.
    static func relay(channel: String) -> String {
        #"""
        (() => {
          const channel = '\#(channel)';
          window.addEventListener(channel + 'q', (event) => {
            let request;
            try { request = JSON.parse(event.detail); } catch (error) { return; }
            if (!request || typeof request.id !== 'string') return;
            const answer = (result) => window.dispatchEvent(
              new CustomEvent(channel + 'a', { detail: JSON.stringify(Object.assign({ id: request.id }, result)) })
            );
            window.webkit.messageHandlers.notifications.postMessage(request.message)
              .then((value) => answer({ value }), (error) => answer({ error: String(error) }));
          });
          // Scripts of two worlds start in no set order: the API resends what
          // it asked before this relay listened.
          window.dispatchEvent(new CustomEvent(channel + 'r'));
        })();
        """#
    }

    /// The `Notification` class (its helpers are private to the script).
    private static let api = #"""
      if (!window.isSecureContext) return;

      // Kept before the page's own scripts run: the page can't intercept them.
      const parse = JSON.parse;
      const stringify = JSON.stringify;
      const dispatch = window.dispatchEvent.bind(window);
      const listen = window.addEventListener.bind(window);
      const PageEvent = CustomEvent;
      // Read through the original getter: one the page puts on the prototype
      // would see the event, hence the channel's name.
      const detailOf = Object.getOwnPropertyDescriptor(CustomEvent.prototype, 'detail').get;
      const pending = new Map();
      let nextRequest = 1;
      listen(channel + 'a', (event) => {
        let answer;
        try { answer = parse(detailOf.call(event)); } catch (error) { return; }
        const handlers = answer && pending.get(answer.id);
        if (!handlers) return;
        pending.delete(answer.id);
        if ('error' in answer) handlers.reject(new Error(answer.error)); else handlers.resolve(answer.value);
      });
      const send = (id, message) => dispatch(new PageEvent(channel + 'q', { detail: stringify({ id, message }) }));
      const post = (message) => new Promise((resolve, reject) => {
        const id = String(nextRequest++);
        pending.set(id, { resolve, reject, message });
        send(id, message);
      });
      // The relay started after this script: what it missed is sent again.
      listen(channel + 'r', () => {
        for (const [id, request] of pending) send(id, request.message);
      });
      // The site's saved choice, given by the app for this site only.
      let permission = initial && location.origin === initial.origin ? initial.permission : 'default';
      post({ action: 'permission' }).then((state) => { permission = state; }, () => {});

      const shown = new Map();
      const ids = new WeakMap();
      let nextID = 1;

      const fire = (notification, type) => {
        const event = new Event(type, { cancelable: type === 'click' });
        const handler = notification['on' + type];
        if (typeof handler === 'function') handler.call(notification, event);
        notification.dispatchEvent(event);
      };

      class Notification extends EventTarget {
        constructor(title, options = {}) {
          if (arguments.length === 0) {
            throw new TypeError("Failed to construct 'Notification': 1 argument required, but only 0 present.");
          }
          super();
          options = options || {};
          const id = String(nextID++);
          ids.set(this, id);
          this.title = String(title);
          this.body = options.body == null ? '' : String(options.body);
          this.tag = options.tag == null ? '' : String(options.tag);
          this.icon = options.icon == null ? '' : String(options.icon);
          this.data = options.data === undefined ? null : options.data;
          this.silent = Boolean(options.silent);
          this.requireInteraction = Boolean(options.requireInteraction);
          this.dir = options.dir || 'auto';
          this.lang = options.lang || '';
          this.onclick = null;
          this.onshow = null;
          this.onclose = null;
          this.onerror = null;
          post({ action: 'show', id, title: this.title, body: this.body, tag: this.tag, silent: this.silent })
            .then((isShown) => {
              if (isShown) {
                shown.set(id, this);
                fire(this, 'show');
              } else {
                fire(this, 'error');
              }
            }, () => fire(this, 'error'));
        }

        close() {
          const id = ids.get(this);
          if (!shown.has(id)) return;
          shown.delete(id);
          post({ action: 'close', id }).catch(() => {});
          fire(this, 'close');
        }

        static get permission() { return permission; }
        static get maxActions() { return 0; }

        static requestPermission(callback) {
          const result = post({ action: 'request' }).then(
            (state) => { permission = state; return state; },
            () => permission
          );
          if (typeof callback === 'function') result.then(callback);
          return result;
        }
      }

      Object.defineProperty(window, 'Notification', { value: Notification, writable: true, configurable: true });

    """#

    /// A notification clicked or closed in Notification Center.
    private static func clicks(channel: String) -> String {
        #"""
          // A notification clicked or closed in Notification Center (sent from
          // the app's world, as a JSON string).
          listen(channel, (event) => {
            let detail = [];
            try {
              const value = detailOf.call(event);
              detail = typeof value === 'string' ? parse(value) : [];
            } catch (error) {}
            const [id, type] = Array.isArray(detail) ? detail : [];
            const notification = shown.get(String(id));
            if (!notification) return;
            if (type === 'close') shown.delete(String(id));
            fire(notification, type);
          });

        """#
    }

    private static let permissions = #"""
      // navigator.permissions.query({ name: 'notifications' }) follows the same
      // choice: WebKit answers "prompt" for notifications whatever the site's
      // choice (apps have no notifications of its own). WebKit's own query and
      // PermissionStatus; only the state read for notifications is the choice,
      // through the prototype's getter (the object has no property of its own).
      const stateOf = typeof PermissionStatus === 'function'
        && Object.getOwnPropertyDescriptor(PermissionStatus.prototype, 'state');
      if (stateOf && typeof stateOf.get === 'function') {
        const nameOf = Object.getOwnPropertyDescriptor(PermissionStatus.prototype, 'name');
        const readState = stateOf.get;
        const readName = nameOf && nameOf.get;
        const getter = Object.getOwnPropertyDescriptor({
          get state() {
            const state = readState.call(this);
            if (!readName || readName.call(this) !== 'notifications') return state;
            return permission === 'default' ? 'prompt' : permission;
          }
        }, 'state').get;
        Object.defineProperty(PermissionStatus.prototype, 'state', {
          get: getter, enumerable: stateOf.enumerable, configurable: stateOf.configurable
        });
      }
    })();
    """#
}
