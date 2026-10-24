import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {translate,language,languages,languageKey} from '../download-site/public/app/language.mjs';
const catalog=JSON.parse(readFileSync(new URL('../download-site/public/app/translations.json',import.meta.url),'utf8'));
assert.deepEqual(Object.keys(languages),['en','es','zh-Hans']);
assert.equal(translate('My Jars','es',catalog),'Mis frascos');
assert.equal(translate('My Jars','zh-Hans',catalog),'我的存钱罐');
assert.equal(translate('My Jars','en',catalog),'My Jars');
assert.equal(translate('Jordan’s custom task','es',catalog),'Jordan’s custom task');
for(const translations of Object.values(catalog)){assert.ok(translations.es);assert.ok(translations['zh-Hans']);}
let saved='es';globalThis.localStorage={getItem:key=>key===languageKey?saved:null};
assert.equal(language(),'es');saved='unknown';assert.equal(language(),'en');
const native=JSON.parse(readFileSync(new URL('../Sources/PocketCrew/Resources/translations.json',import.meta.url),'utf8'));
assert.deepEqual(native,catalog);
console.log('Languages: Spanish, Chinese, fallback, saved preference and shared catalog passed.');
