export async function checkForUpdates(){
  if(!navigator.onLine)throw Error('Connect to the internet, then check for updates again.');
  const response=await fetch('/app/sw.js',{cache:'no-store'});
  if(!response.ok)throw Error('Could not check for updates. Please try again.');
  const registration=await navigator.serviceWorker?.getRegistration('/app/');
  if(registration){
    await registration.update();
    if(registration.installing){
      const worker=registration.installing;
      await new Promise((resolve,reject)=>{
        const timeout=setTimeout(()=>{worker.removeEventListener('statechange',changed);reject(Error('The update is taking longer than expected. Try again shortly.'));},20000);
        function changed(){if(['installed','activated','redundant'].includes(worker.state)){clearTimeout(timeout);worker.removeEventListener('statechange',changed);worker.state==='redundant'?reject(Error('The update could not be downloaded. Please try again.')):resolve();}}
        worker.addEventListener('statechange',changed);changed();
      });
    }
    if(registration.waiting){
      await new Promise((resolve,reject)=>{
        const timeout=setTimeout(()=>{navigator.serviceWorker.removeEventListener('controllerchange',changed);reject(Error('Close other PocketCrew windows and try again.'));},10000);
        function changed(){clearTimeout(timeout);navigator.serviceWorker.removeEventListener('controllerchange',changed);resolve();}
        navigator.serviceWorker.addEventListener('controllerchange',changed);
        registration.waiting.postMessage({type:'ACTIVATE_UPDATE'});
      });
    }
  }
  // Only reload application files. Never clear the family or remembered account.
  location.reload();
}
