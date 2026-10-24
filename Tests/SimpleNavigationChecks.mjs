import assert from 'node:assert/strict';
import {mainSection,sectionTabs} from '../download-site/public/app/simple-navigation.mjs';
for(const [page,section] of [['Home','Home'],['Work','Work'],['Payday','Jars'],['Jars','Jars'],['Profile','Settings'],['Settings','Settings']])assert.equal(mainSection(page),section);
assert.match(sectionTabs('Jars',true),/data-act="shop"/);
assert.match(sectionTabs('Payday',false),/data-page="Jars"/);
assert.match(sectionTabs('Settings',true),/>Family</);
assert.match(sectionTabs('Settings',false),/>Profile</);
assert.equal(sectionTabs('Home',true),'');
console.log('Four-section navigation preserves money, payday, shopping, family and profile routes.');
