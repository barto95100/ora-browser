/// The standard `Notification` API, which WebKit leaves out of apps, backed by
/// `WebNotificationBridge`. Secure pages only, like in every browser.
enum WebNotificationScript {
    static let source = #"""
    (() => {
      const bridge = window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.oraNotifications;
      if (!bridge || !window.isSecureContext || window.__oraNotificationEvent) return;

      const post = (message) => bridge.postMessage(message);
      let permission = 'default';
      post({ action: 'permission' }).then((state) => { permission = state; }, () => {});

      const shown = new Map();
      let nextID = 1;

      class Notification extends EventTarget {
        constructor(title, options = {}) {
          if (arguments.length === 0) {
            throw new TypeError("Failed to construct 'Notification': 1 argument required, but only 0 present.");
          }
          super();
          options = options || {};
          const id = String(nextID++);
          Object.defineProperty(this, '__oraID', { value: id });
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
                this.__oraFire('show');
              } else {
                this.__oraFire('error');
              }
            }, () => this.__oraFire('error'));
        }

        close() {
          const id = this.__oraID;
          if (!shown.has(id)) return;
          shown.delete(id);
          post({ action: 'close', id }).catch(() => {});
          this.__oraFire('close');
        }

        __oraFire(type) {
          const event = new Event(type, { cancelable: type === 'click' });
          const handler = this['on' + type];
          if (typeof handler === 'function') handler.call(this, event);
          this.dispatchEvent(event);
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
      Object.defineProperty(window, '__oraNotificationEvent', {
        value: (id, type) => {
          const notification = shown.get(String(id));
          if (!notification) return;
          if (type === 'close') shown.delete(String(id));
          notification.__oraFire(type);
        }
      });

      // navigator.permissions.query({ name: 'notifications' }) follows the same choice.
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
