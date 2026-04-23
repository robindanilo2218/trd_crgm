const CACHE_NAME = 'tradestats-v4';

self.addEventListener('message', event => {
    if (event.data && event.data.action === 'skipWaiting') {
        self.skipWaiting();
    }
});
const urlsToCache = [
    './',
    './index.html',
    './manifest.json',
    './app.js',
    './style.css',
    './tailwind.config.js',
    './tailwindcss.js'
];

self.addEventListener('install', event => {
    event.waitUntil(
        caches.open(CACHE_NAME)
            .then(cache => cache.addAll(urlsToCache))
    );
});

self.addEventListener('fetch', event => {
    event.respondWith(
        caches.match(event.request)
            .then(response => response || fetch(event.request))
    );
});