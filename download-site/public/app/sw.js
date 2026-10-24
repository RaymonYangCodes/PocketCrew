const CACHE='pocketcrew-phone-v33';
const ICONS=['/app/preset-sections.mjs','/app/icon-180.png?v=2','/app/icon.svg?v=2','/app/icon-192.png?v=2','/app/icon-512.png?v=2'];
const FILES=['/app/','/app/index.html','/app/style.css','/app/mac-theme.css','/app/mac-theme.js','/app/app.js','/app/domain.mjs','/app/cloud.mjs','/app/cloud-ui.mjs','/app/cloud-actions.mjs','/app/manifest.webmanifest','/app/icon.svg','/app/icon-192.png','/app/icon-512.png'];
FILES.push('/app/shopping.mjs','/app/shopping-domain.mjs','/app/shopping.css');
FILES.push('/app/add-money.mjs');
FILES.push('/app/simple-navigation.mjs');
FILES.push('/app/language.mjs','/app/translations.json');
FILES.push(...ICONS);
FILES.push('/app/install-state.mjs');
FILES.push('/app/family-setup.mjs');
FILES.push('/app/app-updates.mjs');
FILES.push('/app/password-reset.mjs');
FILES.push('/app/goal-progress.mjs');
self.addEventListener('message',event=>{if(event.data?.type==='ACTIVATE_UPDATE')self.skipWaiting();});
FILES.push('/app/walkthrough.mjs','/app/walkthrough.css');
self.addEventListener('install',event=>event.waitUntil(caches.open(CACHE).then(cache=>cache.addAll(FILES))));
// Network-first pages pick up editing controls immediately; the new worker takes
// over after old tabs close without discarding an in-progress form.
self.addEventListener('activate',event=>event.waitUntil(caches.keys().then(keys=>Promise.all(keys.filter(k=>k.startsWith('pocketcrew-phone-')&&k!==CACHE).map(k=>caches.delete(k)))).then(()=>self.clients.claim())));
self.addEventListener('fetch',event=>{
  const url=new URL(event.request.url);
  if(event.request.method!=='GET'||url.origin!==self.location.origin||!FILES.includes(url.pathname))return;
  event.respondWith(fetch(event.request).then(response=>{if(response.ok){const copy=response.clone();caches.open(CACHE).then(cache=>cache.put(event.request,copy));}return response;}).catch(()=>caches.match(event.request)));
});
