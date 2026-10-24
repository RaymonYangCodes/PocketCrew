export const languages={en:'English',es:'Español','zh-Hans':'简体中文'};
export const languageKey='pocketcrew.language';
let catalog={};
export function language(){try{const value=localStorage.getItem(languageKey);return value in languages?value:'en';}catch{return 'en';}}
export function translate(key,locale=language(),dictionary=catalog){return dictionary[key]?.[locale]||key;}
export const t=translate;
export function languageSettings(){return `<article class="card"><h2 data-i18n="Language">${t('Language')}</h2><label for="app-language" data-i18n="Language">${t('Language')}</label><select id="app-language">${Object.entries(languages).map(([id,name])=>`<option value="${id}" ${id===language()?'selected':''}>${name}</option>`).join('')}</select><p data-i18n="Choose your language. Your family’s words stay unchanged.">${t('Choose your language. Your family’s words stay unchanged.')}</p></article>`;}
export function localize(root=document){
  document.documentElement.lang=language();
  root.querySelectorAll('[data-i18n]').forEach(el=>{const value=t(el.dataset.i18n);if(el.textContent!==value)el.textContent=value;});
}
export function installLanguage(render){
  fetch(new URL('./translations.json',import.meta.url)).then(r=>{if(!r.ok)throw Error('Translations unavailable');return r.json();}).then(data=>{catalog=data;render();localize();}).catch(()=>{});
  document.addEventListener('change',e=>{if(e.target.id!=='app-language')return;const value=e.target.value;if(!(value in languages))return;try{localStorage.setItem(languageKey,value);}catch{e.target.value=language();return;}render();localize();});
  new MutationObserver(()=>localize()).observe(document.body,{childList:true,subtree:true});
  localize();
}
