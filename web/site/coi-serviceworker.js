/*! coi-serviceworker: cross-origin isolation for this site's threaded wasm build.
 * The build uses -pthread, so it needs SharedArrayBuffer, which browsers give only to a
 * crossOriginIsolated page (COOP same-origin + COEP). GitHub Pages cannot set response headers,
 * so this worker adds them to every same-origin response. COEP is credentialless where the
 * browser supports it and require-corp on Apple WebKit, which does not.
 * Adapted from daslang's site/coi-serviceworker.js, itself from github.com/gzuidhof/coi-serviceworker (MIT). */
function coiUsesCredentialless(ua) {
    ua = ua || "";
    return !(/AppleWebKit\//.test(ua) && !/Chrome\/|Chromium\/|Android/.test(ua));
}

if (typeof window === "undefined") {
    var COEP = coiUsesCredentialless(self.navigator && self.navigator.userAgent) ? "credentialless" : "require-corp";
    self.addEventListener("install", function () { self.skipWaiting(); });
    self.addEventListener("activate", function (e) { e.waitUntil(self.clients.claim()); });
    self.addEventListener("fetch", function (event) {
        var r = event.request;
        if (r.cache === "only-if-cached" && r.mode !== "same-origin") return;
        var url;
        try { url = new URL(r.url); } catch (e) { return; }
        if (url.origin !== self.location.origin) return;
        event.respondWith(fetch(r).then(function (response) {
            if (response.status === 0) return response;
            var headers = new Headers(response.headers);
            headers.set("Cross-Origin-Embedder-Policy", COEP);
            if (r.mode === "navigate") headers.set("Cross-Origin-Opener-Policy", "same-origin");
            headers.set("Cross-Origin-Resource-Policy", "cross-origin");
            return new Response(response.body, { status: response.status, statusText: response.statusText, headers: headers });
        }).catch(function (e) { console.error(e); return Response.error(); }));
    });
} else {
    (function () {
        if (!window.isSecureContext || window.crossOriginIsolated || !("serviceWorker" in navigator)) return;
        if (navigator.serviceWorker.controller) return;
        // reload once, after the worker is active and controls the page: a reload before that comes
        // back uncontrolled, so not isolated
        var reloadOnce = function () {
            if (window.sessionStorage.getItem("coiReloaded")) return;
            window.sessionStorage.setItem("coiReloaded", "1");
            window.location.reload();
        };
        navigator.serviceWorker.addEventListener("controllerchange", reloadOnce);
        var scriptUrl = (document.currentScript && document.currentScript.src) || "coi-serviceworker.js";
        navigator.serviceWorker.register(scriptUrl).then(function () {
            return navigator.serviceWorker.ready;
        }).then(reloadOnce).catch(function (e) { console.error("coi-serviceworker registration failed:", e); });
    })();
}
