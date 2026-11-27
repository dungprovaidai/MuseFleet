/* Node checks the shipped engine's state machine. XCTest separately exercises real WebKit/DOM behavior. */
"use strict";
const assert = require("node:assert/strict");
const { readFileSync } = require("node:fs");
const { join } = require("node:path");
const { randomUUID } = require("node:crypto");
const vm = require("node:vm");
const { test } = require("node:test");
const engine = readFileSync(join(__dirname, "../App/Browser/CompletionObserver.js"), "utf8");
const adapter = {
    id: "fixture-v1", origin: "https://musefleet-fixture.invalid",
    containerSelector: "[data-fixture-conversation]", itemSelector: "[data-fixture-id]",
    idAttribute: "data-fixture-id", stateAttribute: "data-fixture-state",
    streamingValue: "streaming", completedValue: "complete"
};

function item(id, state) {
    return {
        id, state,
        getAttribute(name) {
            if (name === adapter.idAttribute) return this.id;
            if (name === adapter.stateAttribute) return this.state;
            throw new Error("Observer attempted to read an unapproved attribute");
        },
        get textContent() { throw new Error("Observer must never read message or credential text"); }
    };
}

function fixture(items = [], options = {}) {
    const messages = [];
    const listeners = new Map();
    let mutationCallback;
    let disconnected = false;
    let observeOptions;
    let container = { querySelectorAll: selector => {
        assert.equal(selector, adapter.itemSelector);
        return items;
    }};
    const document = {
        hidden: false, documentElement: {},
        querySelector(selector) { assert.equal(selector, adapter.containerSelector); return container; },
        addEventListener: (name, handler) => listeners.set(name, handler),
        removeEventListener: name => listeners.delete(name),
        get cookie() { throw new Error("Observer must not inspect cookies"); },
        get body() { throw new Error("Observer must not scan the entire page's text"); }
    };
    const context = vm.createContext({
        document, location: new URL((options.origin || adapter.origin) + "/conversation?fixture=1#ignored"),
        URL, TextEncoder, crypto: { randomUUID }, queueMicrotask,
        addEventListener: (name, handler) => listeners.set(name, handler),
        removeEventListener: name => listeners.delete(name),
        webkit: { messageHandlers: { museFleetObserver: { postMessage: raw => {
            assert.ok(Buffer.byteLength(raw) <= 4096);
            messages.push(JSON.parse(raw));
        }}}},
        MutationObserver: class {
            constructor(callback) { mutationCallback = callback; }
            observe(_, config) { observeOptions = config; }
            disconnect() { disconnected = true; }
        }
    });
    vm.runInContext(options.subframe ? "globalThis.top = {};" : "globalThis.top = globalThis;", context);
    vm.runInContext(engine, context);
    function install(config = adapter) {
        disconnected = false;
        vm.runInContext(`globalThis.MuseFleetObserver = MuseFleetObserverEngine.install(${JSON.stringify(config)});`, context);
    }
    install(options.adapter || adapter);
    return {
        items, messages, context, document,
        completed: () => messages.filter(message => message.kind === "completed"),
        options: () => observeOptions,
        disconnected: () => disconnected,
        install,
        stop: () => vm.runInContext("MuseFleetObserver.stop()", context),
        replaceContainer() { container = { querySelectorAll: () => items }; },
        removeContainer() { container = null; },
        async mutate() { if (!disconnected) mutationCallback?.(); await Promise.resolve(); },
        async visibility(hidden) {
            document.hidden = hidden;
            listeners.get("visibilitychange")?.();
            await Promise.resolve();
        }
    };
}

test("history baselines silently and an in-progress initial item completes once", async () => {
    const stream = item("baseline", "streaming");
    const f = fixture([item("history", "complete"), stream]);
    assert.equal(f.messages[0].kind, "ready");
    assert.equal(f.completed().length, 0);
    for (let token = 0; token < 20; token++) await f.mutate();
    assert.equal(f.completed().length, 0);
    stream.state = "complete";
    await f.mutate();
    assert.deepEqual(f.completed().map(message => message.itemID), ["baseline"]);
    assert.equal(f.completed()[0].conversationURL, adapter.origin + "/conversation");
    stream.state = "streaming";
    await f.mutate();
    stream.state = "complete";
    await f.mutate();
    assert.equal(f.completed().length, 1);
});

test("new streaming items produce no token or generic text-diff events", async () => {
    const f = fixture([item("history", "complete")]);
    const stream = item("new", "streaming");
    f.items.push(stream);
    for (let token = 0; token < 30; token++) await f.mutate();
    assert.equal(f.completed().length, 0);
    assert.equal(f.options().characterData, undefined);
    assert.deepEqual(Array.from(f.options().attributeFilter), [adapter.idAttribute, adapter.stateAttribute]);
    stream.state = "complete";
    await f.mutate();
    assert.equal(f.completed().length, 1);
    assert.deepEqual(Object.keys(f.completed()[0]).sort(), ["conversationURL", "documentID", "itemID", "kind", "version"]);
});

test("completed items inserted after the initial scan are history, including re-rendered IDs", async () => {
    const f = fixture();
    f.items.push(item("new-result", "complete"));
    await f.mutate();
    assert.equal(f.completed().length, 0);
    f.items.splice(0, 1, item("new-result", "complete"));
    await f.mutate();
    assert.equal(f.completed().length, 0);
});

test("stopped/reinstalled and hidden/resumed observers baseline missed history", async () => {
    const stream = item("stream", "streaming");
    const f = fixture([stream]);
    await f.visibility(true);
    stream.state = "complete";
    await f.mutate();
    await f.visibility(false);
    assert.equal(f.completed().length, 0);
    f.stop();
    f.items.push(item("missed", "complete"));
    f.install();
    assert.equal(f.completed().length, 0);
});

test("a route change or replaced conversation container establishes another baseline", async () => {
    const f = fixture([item("history", "complete")]);
    f.context.location.href = adapter.origin + "/another-conversation";
    f.items.push(item("other-history", "complete"));
    await f.mutate();
    assert.equal(f.completed().length, 0);
    f.replaceContainer();
    f.items.push(item("loaded-history", "complete"));
    await f.mutate();
    assert.equal(f.completed().length, 0);
    const live = item("live", "streaming");
    f.items.push(live);
    await f.mutate();
    live.state = "complete";
    await f.mutate();
    assert.equal(f.completed().length, 1);
});

test("missing container waits for fixture markers without announcing detection ready", async () => {
    const f = fixture();
    f.removeContainer();
    await f.mutate();
    const count = f.messages.length;
    await f.mutate();
    assert.equal(f.messages.length, count);
    f.replaceContainer();
    f.items.push(item("delayed-history", "complete"));
    await f.mutate();
    assert.equal(f.completed().length, 0);
});

test("untrusted origin and subframes fail closed", () => {
    for (const config of [{ origin: "http://musefleet-fixture.invalid" }, { origin: "https://attacker.invalid" }, { subframe: true }]) {
        const f = fixture([], config);
        assert.equal(f.completed().length, 0);
        assert.equal(f.messages.at(-1).kind, "unavailable");
    }
});

test("oversized history stops and unbounded identifiers are not sent", async () => {
    const large = fixture(Array.from({ length: 2001 }, (_, n) => item(`item-${n}`, "complete")));
    assert.equal(large.messages.at(-1).kind, "unavailable");
    assert.equal(large.disconnected(), true);
    const f = fixture();
    f.items.push(item("x".repeat(129), "complete"), item("bad/id", "complete"), item("valid", "typing"));
    await f.mutate();
    assert.equal(f.completed().length, 0);
});

test("invalid adapters fail closed and never use body text fallback", () => {
    const f = fixture([], { adapter: { ...adapter, stateAttribute: "value" } });
    assert.equal(f.messages.at(-1).kind, "unavailable");
    assert.equal(f.completed().length, 0);
});
