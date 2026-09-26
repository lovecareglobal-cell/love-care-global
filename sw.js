
// LOVE CARE GLOBAL HOME NURSING - Service Worker for PWABuilder
// PWABuilder requires service worker for offline capability

const CACHE_NAME = 'lovecare-v2.1.0';
const urlsToCache = [
  './',
  './index.html',
  './manifest.json',
  './icon-192.png',
  './icon-512.png',
  './icon-1024.png',
  './terms.html',
  './privacy-policy.html',
  './delete-account.html'
];

self.addEventListener('install', function(event) {
  event.waitUntil(
    caches.open(CACHE_NAME)
      .then(function(cache) {
        console.log('✅ PWA Cache opened for PWABuilder');
        return cache.addAll(urlsToCache);
      })
  );
});

self.addEventListener('fetch', function(event) {
  event.respondWith(
    caches.match(event.request)
      .then(function(response) {
        // Return cached or fetch
        return response || fetch(event.request);
      }
    )
  );
});

self.addEventListener('activate', function(event) {
  event.waitUntil(
    caches.keys().then(function(cacheNames) {
      return Promise.all(
        cacheNames.map(function(cacheName) {
          if (cacheName !== CACHE_NAME) {
            return caches.delete(cacheName);
          }
        })
      );
    })
  );
});

// For Firebase Messaging - import
importScripts('https://www.gstatic.com/firebasejs/9.22.0/firebase-app-compat.js');
importScripts('https://www.gstatic.com/firebasejs/9.22.0/firebase-messaging-compat.js');

try {
  firebase.initializeApp({
    apiKey: "AIzaSyB52-X1D8Cg-wUDWPds_tR7D8cF82dMdRg",
    authDomain: "web-care-618e8.firebaseapp.com",
    databaseURL: "https://web-care-618e8-default-rtdb.firebaseio.com",
    projectId: "web-care-618e8",
    storageBucket: "web-care-618e8.firebasestorage.app",
    messagingSenderId: "1062578660694",
    appId: "1:1062578660694:web:f94dfe12c929df05bce2f7"
  });
  const messaging = firebase.messaging();
  messaging.onBackgroundMessage(function(payload) {
    console.log('Background message received', payload);
    const notificationTitle = payload.notification.title || 'LOVE CARE GLOBAL HOME NURSING';
    const notificationOptions = {
      body: payload.notification.body || 'New booking received',
      icon: './icon-512.png',
      badge: './icon-192.png'
    };
    self.registration.showNotification(notificationTitle, notificationOptions);
  });
} catch(e) { console.log('Firebase SW init error', e); }
