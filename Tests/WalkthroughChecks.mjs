import assert from 'node:assert/strict';
import {walkthroughSteps} from '../download-site/public/app/walkthrough.mjs';
for(const parent of [true,false]){
  const steps=walkthroughSteps(parent);
  assert.equal(steps.length,10);
  assert.equal(steps[0][0],'Home');assert.equal(steps.at(-1)[0],'Settings');
  assert.ok(steps.every(s=>s.length>=4&&s.every(v=>typeof v==='string'&&v.length)));
  assert.ok(steps.some(s=>s[0]==='Work'));assert.ok(steps.some(s=>s[0]==='Payday'));assert.ok(steps.some(s=>s[0]==='Jars'));
}
assert.ok(walkthroughSteps(false).some(s=>/submit/i.test(s[3])));
assert.ok(walkthroughSteps(true).some(s=>/approv/i.test(s[3])));
console.log('Walkthrough steps passed for parents and children.');
assert.ok(walkthroughSteps(true).some(s=>s[1].includes('[data-act="add-child"]')));
assert.ok(walkthroughSteps(true).some(s=>s[1]==='[data-act="presets"]'));
assert.ok(walkthroughSteps(false).some(s=>s[1]==='[data-act="walkthrough"]'));
