// LOVE CARE GLOBAL HOME NURSING - Service Worker
const CACHE_NAME = 'lovecare-v1';
const urlsToCache = [
  './',
  './index.html',
  './manifest.json',
  './icon-192.png',
  './icon-512.png'
];

self.addEventListener('install', function(event){
  console.log('SW installing...');
  event.waitUntil(
    caches.open(CACHE_NAME).then(function(cache){
      return cache.addAll(urlsToCache).catch(function(err){
        console.log('Cache addAll error, caching individually', err);
        // Cache individually to avoid failing all if one fails
        return Promise.all(urlsToCache.map(function(url){
          return cache.add(url).catch(function(e){ console.log('Failed to cache', url); });
        }));
      });
    })
  );
  self.skipWaiting();
});

self.addEventListener('activate', function(event){
  console.log('SW activating...');
  event.waitUntil(
    caches.keys().then(function(cacheNames){
      return Promise.all(cacheNames.map(function(cacheName){
        if(cacheName !== CACHE_NAME){
          console.log('Deleting old cache', cacheName);
          return caches.delete(cacheName);
        }
      }));
    })
  );
  self.clients.claim();
});

self.addEventListener('fetch', function(event){
  event.respondWith(
    caches.match(event.request).then(function(response){
      // Return cached or fetch network
      if(response){
        return response;
      }
      return fetch(event.request).then(function(res){
        // Don't cache non-GET or chrome extensions
        if(!res || res.status !== 200 || res.type !== 'basic' && res.type !== 'cors') {
          return res;
        }
        // Clone and cache
        var resToCache = res.clone();
        caches.open(CACHE_NAME).then(function(cache){
          // Only cache same-origin or manifest/icons
          if(event.request.url.includes(self.location.origin) || event.request.url.includes('manifest') || event.request.url.includes('icon')){
            cache.put(event.request, resToCache);
          }
        });
        return res;
      }).catch(function(){
        // Offline fallback
        if(event.request.headers.get('accept') && event.request.headers.get('accept').includes('text/html')){
          return caches.match('./index.html');
        }
      });
    })
  );
});

// Push notifications (for future CEO alerts)
self.addEventListener('push', function(event){
  var data = {title:'LOVE CARE GLOBAL', body:'New notification', icon:'./icon-192.png'};
  if(event.data){
    try{ data = event.data.json(); }catch(e){ data.body = event.data.text(); }
  }
  event.waitUntil(
    self.registration.showNotification(data.title, {
      body: data.body,
      icon: data.icon || './icon-192.png',
      badge: './icon-192.png'
    })
  );
});
