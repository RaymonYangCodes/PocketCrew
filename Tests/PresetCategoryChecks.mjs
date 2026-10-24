import assert from "node:assert/strict";
import {presets} from "../download-site/public/app/domain.mjs";
import {presetSections} from "../download-site/public/app/preset-sections.mjs";
assert.ok(presets.length >= 34);
assert.equal(new Set(presets.map(p=>p[0])).size,presets.length);
for(const p of presets) {
  assert.ok(p[4]);
  if(p[1]==="gig")assert.ok(p[2]>0 && p[2]<300);
}
const html=presetSections(x=>x,x=>String(x));
for(const category of ["Household","Academic","Outdoors","Exercise","Creative","Pet care"])assert.ok(html.includes(`<h3>${category}</h3>`));
for(let i=0;i<presets.length;i++)assert.ok(html.includes(`data-preset="${i}"`));
assert.ok(presetSections(x=>x,String,"data-cloud-preset").includes("data-cloud-preset="));
console.log("Categorized presets: all categories, editable indexes, and rewards under $3 passed.");
