import {presets} from './domain.mjs';

export function presetSections(esc, money, attribute='data-preset') {
  return ['Household','Academic','Outdoors','Exercise','Creative','Pet care'].map(category=>{
    const rows=presets.map((p,i)=>({p,i})).filter(({p})=>p[4]===category);
    if(!rows.length)return '';
    return `<section class="preset-category"><h3>${esc(category)}</h3>${rows.map(({p,i})=>`<button class="preset" ${attribute}="${i}"><span>${esc(p[0])}</span><span>${p[1]==='gig'?money(p[2]):'Unpaid'}</span></button>`).join('')}</section>`;
  }).join('');
}
