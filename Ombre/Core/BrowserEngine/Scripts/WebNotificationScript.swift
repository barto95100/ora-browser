/// The standard `Notification` API, which WebKit leaves out of apps, backed by
/// `WebNotificationBridge`. Secure pages only, like in every browser.
///
/// It must run in the page's world (it gives the page an API), so it leaves
/// nothing else there: its helpers are private to it, and it reaches the app
/// through `relay`, in the app's world, with events named after `channel`, a
/// secret of the page. No handler of the app is in the page's world: Safari's
/// pages have no `window.webkit`, Ombre's neither.
enum WebNotificationScript {
    static func source(channel: String) -> String {
        "(() => {\n  const channel = '\(channel)';\n" + api + clicks(channel: channel) + permissions
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
      let permission = 'default';
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
      // navigator.permissions.query({ name: 'notifications' }) follows the same choice
      // (WebKit itself answers "prompt" for a site denied through this bridge).
      const permissions = navigator.permissions;
      if (permissions && typeof permissions.query === 'function') {
        const query = permissions.query.bind(permissions);
        permissions.query = (descriptor) => {
          if (!descriptor || descriptor.name !== 'notifications') return query(descriptor);
          const status = new EventTarget();
          const state = permission === 'default' ? 'prompt' : permission;
          Object.defineProperty(status, 'name', { value: 'notifications' });
          Object.defineProperty(status, 'state', { value: state });
          status.onchange = null;
          return Promise.resolve(status);
        };
      }
    })();
    """#
}
