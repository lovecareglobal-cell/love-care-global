
// firebase-messaging-sw.js - Love Care Global Home Nursing - FCM Background Push
importScripts('https://www.gstatic.com/firebasejs/10.12.2/firebase-app-compat.js');
importScripts('https://www.gstatic.com/firebasejs/10.12.2/firebase-messaging-compat.js');

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
  console.log('[firebase-messaging-sw.js] Background message ', payload);
  const title = payload.notification?.title || 'ðŸ”” Love Care Global Home Nursing';
  const options = {
    body: payload.notification?.body || 'New booking received - Check dashboard',
    icon: 'https://lovecareglobal-cell.github.io/love-care-global/icon-512.png',
    badge: 'https://lovecareglobal-cell.github.io/love-care-global/icon-192.png',
    vibrate: [200,100,200],
    data: payload.data || {}
  };
  self.registration.showNotification(title, options);
});

self.addEventListener('notificationclick', function(event) {
  event.notification.close();
  event.waitUntil(
    clients.openWindow('https://lovecareglobal-cell.github.io/love-care-global/')
  );
});
