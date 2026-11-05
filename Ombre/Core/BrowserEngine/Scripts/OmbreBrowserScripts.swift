import Foundation

enum OmbreBrowserScripts {
    static func userScripts() -> [BrowserUserScript] {
        var scripts = [
            BrowserUserScript(
                name: "ombre-bridge",
                source: bridgeScript,
                injectionTime: .atDocumentStart,
                forMainFrameOnly: true
            ),
            BrowserUserScript(
                name: "ombre-navigation",
                source: navigationAndMediaScript,
                injectionTime: .atDocumentEnd,
                forMainFrameOnly: true
            )
        ]

        scripts.append(PageTranslatorScript.userScript)

        if let passwordManagerScript = loadResourceScript(named: "password-manager") {
            scripts.append(
                BrowserUserScript(
                    name: "ombre-password-manager",
                    source: passwordManagerScript,
                    injectionTime: .atDocumentEnd,
                    forMainFrameOnly: true
                )
            )
        }

        return scripts
    }

    private static func loadResourceScript(named name: String) -> String? {
        guard let scriptURL = Bundle.main.url(forResource: name, withExtension: "js"),
              let script = try? String(contentsOf: scriptURL, encoding: .utf8)
        else {
            return nil
        }
        return script
    }

    private static let bridgeScript = """
    (function () {
        if (window.__bridge && typeof window.__bridge.postMessage === 'function') {
            return;
        }

        window.__bridge = {
            postMessage: function(name, payload) {
                try {
                    if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers[name]) {
                        window.webkit.messageHandlers[name].postMessage(payload);
                        return true;
                    }
                } catch (error) {}
                return false;
            }
        };
    })();
    """

    private static let navigationAndMediaScript = """
    (function () {
        function post(name, payload) {
            try {
                window.__bridge && window.__bridge.postMessage(name, payload);
            } catch (error) {}
        }

        // Icons declared by the page, like Safari: the app picks and fetches
        // one. Sent again when the page changes them (e.g. an unread counter).
        let lastIcons = null;
        function iconCandidates() {
            return Array.from(document.querySelectorAll('link[rel][href]'))
                .filter(link => /(^|\\s)(icon|apple-touch-icon|apple-touch-icon-precomposed)(\\s|$)/i
                    .test(link.getAttribute('rel')))
                .map(link => ({
                    href: link.href,
                    rel: (link.getAttribute('rel') || '').toLowerCase(),
                    sizes: link.getAttribute('sizes') || '',
                    type: link.getAttribute('type') || ''
                }));
        }
        function notifyIcons() {
            const icons = iconCandidates();
            const key = JSON.stringify(icons);
            if (key === lastIcons) return;
            lastIcons = key;
            post('favicon', JSON.stringify({ page: location.href, icons: icons }));
        }
        notifyIcons();
        if (document.head) {
            let iconTimer = null;
            new MutationObserver(() => {
                if (iconTimer) return;
                iconTimer = setTimeout(() => { iconTimer = null; notifyIcons(); }, 250);
            }).observe(document.head, { childList: true, subtree: true, attributes: true, attributeFilter: ['href', 'rel'] });
        }

        // Only notify the app when the hovered link actually changes, so that
        // moving across child elements of the same anchor does not re-render
        // the link preview on every mouseover.
        let lastHoverURL = '';
        function postHover(url) {
            const value = url || '';
            if (value === lastHoverURL) return;
            lastHoverURL = value;
            post('linkHover', value);
        }

        function currentAnchor(node) {
            return node && node.closest ? node.closest('a[href]') : null;
        }

        function onMouseOver(event) {
            const anchor = currentAnchor(event.target);
            postHover(anchor ? anchor.href : '');
        }

        function onMouseOut(event) {
            const from = currentAnchor(event.target);
            const to = currentAnchor(event.relatedTarget);
            if (from !== to) postHover(to ? to.href : '');
        }

        document.addEventListener('mouseover', onMouseOver, true);
        document.addEventListener('mouseout', onMouseOut, true);
    })();

    (function () {
        if (window.__mediaInstalled) {
            return;
        }
        window.__mediaInstalled = true;

        function post(payload) {
            try {
                window.__bridge && window.__bridge.postMessage('mediaEvent', JSON.stringify(payload));
            } catch (error) {}
        }

        // Next/previous only on the players known to have such buttons: a
        // generic "Next" (a carousel, a form step) is not the next track.
        const nextSelectors = [
            '.ytp-next-button',
            'ytmusic-player-bar .next-button',
            '[data-testid="control-button-skip-forward"]',
            '.skipControl__next'
        ];
        const previousSelectors = [
            '.ytp-prev-button',
            'ytmusic-player-bar .previous-button',
            '[data-testid="control-button-skip-back"]',
            '[data-testid="control-button-skip-backward"]',
            '.skipControl__previous'
        ];
        function findButton(selectors) {
            for (const selector of selectors) {
                const element = document.querySelector(selector);
                if (element) return element;
            }
            return null;
        }
        const findNextButton = () => findButton(nextSelectors);
        const findPrevButton = () => findButton(previousSelectors);

        // Only tell the app when the next/previous buttons appear or
        // disappear. Looked up when the media changes state, not on every
        // change of the page.
        let lastCaps = null;
        function caps() {
            const hasNext = !!findNextButton();
            const hasPrevious = !!findPrevButton();
            if (lastCaps && lastCaps.hasNext === hasNext && lastCaps.hasPrevious === hasPrevious) return;
            lastCaps = { hasNext, hasPrevious };
            post({ type: 'caps', hasNext, hasPrevious });
        }

        const stateFrom = (element) => ({
            type: 'state',
            wasPlayed: element && element.__wasPlayed,
            state: element && !element.paused ? 'playing' : 'paused',
            volume: element ? (element.muted ? 0 : element.volume) : undefined,
            title: document.title
        });

        // Only media the user can hear count as "played" and bring up the mini
        // player: not muted autoplay videos (page backgrounds, previews, ads),
        // nor videos without any sound track.
        function isAudible(element) {
            return !element.muted && element.volume > 0 && hasSound(element);
        }

        // Whether the media has a sound track. Unknown until its metadata is
        // loaded, so it is checked again once it plays.
        function hasSound(element) {
            if (element.tagName === 'AUDIO') return true;
            if (element.readyState < HTMLMediaElement.HAVE_METADATA) return false;
            if (!element.audioTracks || element.audioTracks.length > 0) return true;
            // Streams (Media Source on blob: URLs, media streams) may list no
            // tracks: assume they have sound. Files list theirs reliably.
            const source = element.currentSrc || '';
            return source.startsWith('blob:') || !!element.srcObject;
        }

        // Marks playing, audible media as played; returns whether it did.
        function markPlayedIfAudible(element, update) {
            if (element.__wasPlayed || element.paused || !isAudible(element)) return false;
            element.__wasPlayed = true;
            update();
            return true;
        }

        // The media the app was told about, to tell it when they leave the page.
        const tracked = new Set();

        // Media events don't bubble, but listeners on the document in the
        // capture phase see them all: no scan of the page for new media.
        const handlers = {
            play(element, update) {
                if (!markPlayedIfAudible(element, update)) update();
                caps();
            },
            // Playing: the metadata, hence the sound track, is known.
            playing(element, update) {
                markPlayedIfAudible(element, update);
            },
            pause(element, update) {
                update();
                caps();
            },
            ended() {
                post({ type: 'ended' });
            },
            // Leaving Picture in Picture with the video still playing means the
            // user chose "back to tab" (closing the window pauses it): ask the
            // app to show this tab, as Safari does.
            enterpictureinpicture() {
                post({ type: 'pip', state: 'entered' });
            },
            leavepictureinpicture(element) {
                post({ type: 'pip', state: 'left' });
                setTimeout(() => {
                    if (!element.paused) post({ type: 'pipReturn' });
                }, 0);
            },
            volumechange(element, update) {
                // A muted video the user unmutes while it plays now counts.
                markPlayedIfAudible(element, update);
                post({ type: 'volume', volume: element.muted ? 0 : element.volume });
            }
        };
        for (const type of Object.keys(handlers)) {
            document.addEventListener(type, (event) => {
                const element = event.target;
                if (!(element instanceof HTMLMediaElement)) return;
                tracked.add(element);
                handlers[type](element, () => post(stateFrom(element)));
            }, true);
        }

        // Media already playing when the script runs.
        document.querySelectorAll('video, audio').forEach((element) => {
            if (element.paused) return;
            tracked.add(element);
            const update = () => post(stateFrom(element));
            if (!markPlayedIfAudible(element, update)) update();
            caps();
        });

        // One observer for the whole page, that only looks for removed nodes,
        // and only while some media is known. Busy pages (YouTube...) change
        // their DOM constantly: checks are coalesced into one every 250 ms.
        // A media moved elsewhere in the page is still connected by then.
        let checkScheduled = false;
        // The page's media session ends with its last media the user heard;
        // a preview or an ad leaving the page only updates it from what
        // remains. Muted previews left behind don't keep it.
        function checkRemoved() {
            checkScheduled = false;
            let removed = false;
            for (const element of tracked) {
                if (element.isConnected) continue;
                tracked.delete(element);
                removed = true;
            }
            if (!removed) return;
            const played = Array.from(tracked).filter((element) => element.__wasPlayed);
            const current = played.find((element) => !element.paused) || played[0];
            if (current) {
                post(stateFrom(current));
            } else {
                // A next session starts without buttons: tell it again.
                lastCaps = null;
                post({ type: 'removed' });
            }
        }
        new MutationObserver((mutations) => {
            if (checkScheduled || tracked.size === 0) return;
            if (!mutations.some((mutation) => mutation.removedNodes.length > 0)) return;
            checkScheduled = true;
            setTimeout(checkRemoved, 250);
        }).observe(document.documentElement, { childList: true, subtree: true });

        window.__media = {
            active: null,
            _pick() {
                const elements = Array.from(document.querySelectorAll('video, audio'));
                const playing = elements.find((element) => !element.paused);
                this.active = playing || elements[0] || null;
                return this.active;
            },
            play() {
                try { (this._pick() || {}).play(); return true; } catch (error) { return false; }
            },
            pause() {
                try { (this._pick() || {}).pause(); return true; } catch (error) { return false; }
            },
            toggle() {
                const element = this._pick();
                if (!element) return false;
                if (element.paused) {
                    element.play();
                } else {
                    element.pause();
                }
                return true;
            },
            setVolume(value) {
                const element = this._pick();
                if (!element) return false;
                element.muted = false;
                element.volume = Math.max(0, Math.min(1, value));
                post({ type: 'volume', volume: element.volume });
                return true;
            },
            deltaVolume(delta) {
                const element = this._pick();
                if (!element) return false;
                element.muted = false;
                element.volume = Math.max(0, Math.min(1, (element.volume || 0) + delta));
                post({ type: 'volume', volume: element.volume });
                return true;
            },
            next() {
                const element = findNextButton();
                if (!element) return false;
                element.click();
                caps();
                return true;
            },
            previous() {
                const element = findPrevButton();
                if (!element) return false;
                element.click();
                caps();
                return true;
            },
            title() {
                return document.title;
            }
        };

        window.__triggerPiP = function(isActive = false) {
            // Pages can hold several videos (hover previews, ads...): use the
            // one actually playing with sound, not merely the first one. Same
            // rule as the mini player: not muted, and with a sound track.
            const video = Array.from(document.querySelectorAll('video'))
                .find((candidate) => !candidate.paused && isAudible(candidate)) || null;

            if (
                video &&
                video.tagName === 'VIDEO' &&
                !document.pictureInPictureElement &&
                !video.paused &&
                !isActive &&
                isAudible(video)
            ) {
                video.requestPictureInPicture().catch(() => {});
            } else if (isActive && document.pictureInPictureElement) {
                // Only bring the video back when its tab is shown again; leaving
                // a tab whose video is already in Picture in Picture keeps it.
                document.exitPictureInPicture().catch(() => {});
            }
        };

        post({ type: 'ready', title: document.title });
    })();
    """
}
