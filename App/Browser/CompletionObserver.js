/* Runs only in MuseFleet's isolated content world with a separately verified adapter. */
(() => {
    "use strict";
    const MAX_ITEMS = 2000;
    const validID = /^[A-Za-z0-9_.-]{1,128}$/;

    function install(adapter) {
        globalThis.MuseFleetObserver?.stop();
        let stopped = false;
        let observer;
        let queued = false;
        let baselined = false;
        let route;
        let container;
        const states = new Map();
        const documentID = crypto.randomUUID();
        const bridge = globalThis.webkit?.messageHandlers?.museFleetObserver;

        function post(kind, extra = {}) {
            if (stopped || !bridge) return;
            const body = JSON.stringify({ version: 1, kind, documentID, ...extra });
            if (new TextEncoder().encode(body).length <= 4096) bridge.postMessage(body);
        }

        function stop() {
            stopped = true;
            observer?.disconnect();
            states.clear();
            document.removeEventListener("visibilitychange", visibilityChanged);
            globalThis.removeEventListener("pagehide", stop);
        }

        function unavailable() {
            post("unavailable");
            stop();
        }

        function conversationURL() {
            const url = new URL(location.href);
            url.search = "";
            url.hash = "";
            return url.href;
        }

        function scan() {
            queued = false;
            if (stopped || document.hidden) return;
            if (location.origin !== adapter.origin || location.protocol !== "https:") {
                unavailable();
                return;
            }
            const nextRoute = conversationURL();
            const nextContainer = document.querySelector(adapter.containerSelector);
            if (!nextContainer) {
                // Missing/replaced conversation containers must establish a fresh history baseline.
                baselined = false;
                container = null;
                states.clear();
                return;
            }
            if (route !== nextRoute || container !== nextContainer) {
                baselined = false;
                states.clear();
                route = nextRoute;
                container = nextContainer;
            }
            const items = container.querySelectorAll(adapter.itemSelector);
            if (items.length > MAX_ITEMS) { unavailable(); return; }
            for (const item of items) {
                // Read only stable identifiers and explicit state markers, never message text or inputs.
                const id = item.getAttribute(adapter.idAttribute);
                const state = item.getAttribute(adapter.stateAttribute);
                if (!validID.test(id || "")) continue;
                if (state !== adapter.streamingValue && state !== adapter.completedValue) continue;
                const previous = states.get(id);
                const complete = state === adapter.completedValue;
                if (!previous) {
                    if (states.size >= MAX_ITEMS) { unavailable(); return; }
                    // shortcut: first-seen completed items are history; require a verified site cursor before emitting terminal-only inserts.
                    states.set(id, { emitted: complete });
                } else if (!previous.emitted && complete) {
                    previous.emitted = true;
                    if (baselined) post("completed", { itemID: id, conversationURL: route });
                }
            }
            if (!baselined) { baselined = true; post("ready"); }
        }

        function schedule() {
            if (queued || stopped || document.hidden) return;
            queued = true;
            queueMicrotask(() => {
                if (stopped) return;
                try { scan(); } catch { unavailable(); }
            });
        }

        function visibilityChanged() {
            // Resuming a hidden page baselines again; hidden completions are never replayed.
            baselined = false;
            states.clear();
            schedule();
        }

        try {
            const selectors = [adapter.containerSelector, adapter.itemSelector];
            if (location.origin !== adapter.origin || location.protocol !== "https:" ||
                !bridge || globalThis !== globalThis.top ||
                !selectors.every(value => typeof value === "string" && value.length > 0 && value.length <= 256) ||
                ![adapter.idAttribute, adapter.stateAttribute].every(value => /^data-[a-z0-9-]{1,64}$/.test(value)) ||
                !adapter.streamingValue || !adapter.completedValue ||
                adapter.streamingValue === adapter.completedValue) {
                unavailable();
                return { stop };
            }
            observer = new MutationObserver(schedule);
            observer.observe(document.documentElement, {
                subtree: true, childList: true, attributes: true,
                attributeFilter: [adapter.idAttribute, adapter.stateAttribute]
            });
            document.addEventListener("visibilitychange", visibilityChanged);
            globalThis.addEventListener("pagehide", stop, { once: true });
            scan();
        } catch { unavailable(); }
        return { stop };
    }

    globalThis.MuseFleetObserverEngine = Object.freeze({ install });
})();
