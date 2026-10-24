// Original PocketCrew icon geometry; no external fonts, images, or tracking.
import {t} from './language.mjs';
export function icon(name) {
  const shapes={
    spend:'<path d="M4 7h15v13H4a2 2 0 0 1-2-2V6a2 2 0 0 1 2-2h13v3M16 12h6v5h-6z"/><circle cx="18" cy="14.5" r=".6"/>',
    save:'<path d="M20 3C10 2 3 5 4 12c1 8 12 9 16-9Z"/><path d="M3 21c2-7 6-10 12-13M9 13l6 1"/>',
    give:'<path d="M20.7 5.8C17.5 2.3 13.9 4 12 6 10.1 4 6.5 2.3 3.3 5.8-.4 10 4.6 15.8 12 21c7.4-5.2 12.4-11 8.7-15.2Z"/>',
    Home:'<path d="m2 11 10-8 10 8M5 10v11h5v-7h4v7h5V10"/>',
    Work:'<circle cx="12" cy="12" r="9"/><path d="m7 12 3 3 7-7"/>',
    Payday:'<path d="m12 2 2.5 7.5L22 12l-7.5 2.5L12 22l-2.5-7.5L2 12l7.5-2.5ZM20 2v4M18 4h4"/>',
    Jars:'<path d="m12 2 9 5v10l-9 5-9-5V7ZM3 7l9 5 9-5M12 12v10M7 4l9 5"/>',
    Profile:'<circle cx="12" cy="8" r="4"/><path d="M4 22v-3c0-8 16-8 16 0v3"/>',
    Settings:'<circle cx="12" cy="12" r="4"/><path d="M12 2v3M12 19v3M2 12h3M19 12h3M5 5l2 2M17 17l2 2M5 19l2-2M17 7l2-2"/>',
    play:'<path d="m7 4 14 8-14 8Z"/>',
    calendar:'<rect x="3" y="5" width="18" height="16" rx="3"/><path d="M7 2v6M17 2v6M3 11h18M7 15h2M13 15h2"/>'
  };
  return `<svg viewBox="0 0 24 24" width="24" height="24" aria-hidden="true" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">${shapes[name]||shapes.Work}</svg>`;
}
export function welcome() {
  return `<section class="mac-welcome simple-welcome"><div class="welcome-copy"><div class="welcome-brand"><img src="/app/icon.svg?v=2" width="64" height="64" alt=""><span><b>PocketCrew</b><small>Earn it. Split it. Grow it.</small></span></div><h1>Welcome to PocketCrew</h1><p class="welcome-subtitle">Family tasks, pocket money, and savings goals.</p><div class="welcome-buttons"><button data-act="cloud-login" data-i18n="Sign in">Sign in</button><button class="quiet" data-act="new-family" data-i18n="Create a family">Create a family</button><button class="quiet" data-act="child-join" data-i18n="Join a family">Join a family</button></div><p class="phone-disclosure">Create a family with Google and use it on your phone or Mac. No Mac needed to get started.</p><p class="welcome-fineprint">A learning ledger, not a bank. No real money is held or moved.</p></div></section>`;
}
export function finishTheme(state, actor, page) {
  document.body.classList.toggle('welcome-screen',!state);
  document.body.classList.toggle('app-screen',!!actor);
  document.querySelectorAll('.jars').forEach(group=>group.querySelectorAll('.jar').forEach((el,i)=>{
    const name=['spend','save','give'][i];el.dataset.jar=name;
    const symbol=el.querySelector('.symbol');if(symbol)symbol.innerHTML=icon(name);
  }));
  document.querySelectorAll('nav [data-page]').forEach(b=>{b.querySelector('span').innerHTML=icon(b.dataset.page);});
  const h=document.querySelector('main h1');
  if(state&&actor&&h){const titles={Work:actor==='parent'?'Tasks':'My Tasks',Jars:actor==='parent'?'Family Jars':'My Jars',Payday:'Payday',Settings:'Settings',Profile:actor==='parent'?'Family':'Profile'};if(titles[page])h.textContent=t(titles[page]);}
  if(state&&actor==='parent'&&page==='Home'&&h){
    h.textContent=state.demo?'Hi, Maya':'Hi, parent';
    if(h.nextElementSibling?.matches('p'))h.nextElementSibling.textContent=`Here’s what’s happening in ${state.name}.`;
    const summary=document.createElement('section');summary.className='mac-summary';summary.setAttribute('aria-label','Family overview');
    const pending=state.earnings.filter(e=>!e.paydayId).reduce((n,e)=>n+e.amount,0);
    const saved=state.ledger.filter(t=>t.jar==='save').reduce((n,t)=>n+t.amount,0);
    const d=new Date(),today=`${d.getFullYear()}-${String(d.getMonth()+1).padStart(2,'0')}-${String(d.getDate()).padStart(2,'0')}`;
    const usd=n=>new Intl.NumberFormat(state.locale?.replace('_','-')||'en-US',{style:'currency',currency:state.currency||'USD'}).format(n/100);
    summary.innerHTML=[[state.work.filter(w=>w.status==='awaitingApproval').length,'Waiting for review','Work','spend'],[usd(pending),'Next payday','Payday','sun'],[state.work.filter(w=>w.due===today&&!['approved','paid','rejected'].includes(w.status)).length,'Due today','calendar','give'],[usd(saved),'Family savings','save','save']].map(([value,label,key,color])=>`<div class="summary-tile"><span class="jar-icon ${color}">${icon(key)}</span><strong>${value}</strong><small>${label}</small></div>`).join('');
    h.nextElementSibling.after(summary);
  }
}
