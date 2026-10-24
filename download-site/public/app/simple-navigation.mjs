import {t} from './language.mjs';
export const mainSection=page=>({Payday:'Jars',Profile:'Settings'})[page]||page;
export function sectionTabs(page,parent){
  const section=mainSection(page);
  if(!['Jars','Settings'].includes(section))return '';
  const items=section==='Jars'?[['Jars','Jars & goals'],['Payday','Payday']]:[['Settings','Settings'],['Profile',parent?'Family':'Profile']];
  return `<div class="section-tabs" role="navigation" aria-label="${t(section==='Jars'?'Jars':'Settings')}">${items.map(([key,title])=>`<button class="quiet" data-page="${key}" ${page===key?'aria-current="page"':''}>${t(title)}</button>`).join('')}${section==='Jars'?'<button class="quiet" data-act="shop" data-i18n="Shop">Shop</button>':''}</div>`;
}
