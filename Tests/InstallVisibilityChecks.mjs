import assert from 'node:assert/strict';
import {bindInstallVisibility} from '../download-site/public/app/install-state.mjs';
function fixture(mode, ios=false){
  const events={}, queries=[];
  const win={matchMedia(query){const m={matches:query===`(display-mode: ${mode})`,addEventListener(_,f){this.change=f;}};queries.push(m);return m;},addEventListener(n,f){events[n]=f;}};
  const button={hidden:false};bindInstallVisibility(button,win,{standalone:ios});
  return {button,events,queries};
}
assert.equal(fixture('browser').button.hidden,false);
for(const mode of ['standalone','minimal-ui','window-controls-overlay'])assert.equal(fixture(mode).button.hidden,true);
assert.equal(fixture('browser',true).button.hidden,true);
const live=fixture('browser');live.queries[0].matches=true;live.queries[0].change();assert.equal(live.button.hidden,true);
live.queries[0].matches=false;live.events.pageshow();assert.equal(live.button.hidden,false);
live.events.appinstalled();assert.equal(live.button.hidden,true);
console.log('Install visibility passed: browser, iOS, desktop app modes, mode changes, pageshow and installation.');
