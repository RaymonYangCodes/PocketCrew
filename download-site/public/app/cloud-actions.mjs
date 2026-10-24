import {sendCloudCommand} from './cloud.mjs';
import {presetSections} from './preset-sections.mjs';
import {presets,cents,allocation,pending,uid,localDate} from './domain.mjs';

// Forms send narrow commands; no client can replace the native snapshot through here.
export function installCloudActions(ctx){
  const $=s=>document.querySelector(s),esc=ctx.esc;
  const field=(id,label,type='text',value='',extra='')=>`<label for="${id}">${label}</label><input id="${id}" type="${type}" value="${esc(value)}" ${extra}>`;
  const options=()=>ctx.state().children.map(c=>`<option value="${c.id}">${esc(c.name)}</option>`).join('');
  const footer=label=>`<p id="cloud-command-error" class="error" role="alert"></p><button type="submit" class="button-full">${label}</button>`;
  let busy=false;
  function form(title,html,label,action,data,{sensitive=false}={}){
    if(sensitive&&!ctx.hasPin()){ctx.setupPin();return;}
    const key=uid(),snapshot=ctx.state(),access=ctx.access(),generation=ctx.generation();
    ctx.modal(title,`<form id="cloud-command">${html}${sensitive?field('cloud-confirm-pin','Parent passcode for this browser','password','','inputmode="numeric" required'):''}${footer(label)}</form>`);
    const formElement=$('#cloud-command');
    if(action==='schedule'){
      const update=()=>{const custom=$('#cloud-frequency').value==='custom';$('#custom-days-row').hidden=!custom;$('#cloud-custom-days').disabled=!custom;$('#cloud-custom-days').required=custom;};
      $('#cloud-frequency').onchange=update;update();
    }
    formElement.onsubmit=async event=>{
      event.preventDefault();if(busy)return;busy=true;const button=event.submitter;button.disabled=true;
      try{
        if(sensitive)await ctx.checkPin($('#cloud-confirm-pin').value);
        if(generation!==ctx.generation())throw Error('This profile was locked. Open it again to continue.');
        const next=await sendCloudCommand(snapshot,action,data(),key,access);
        if(generation!==ctx.generation())return;
        ctx.accept(next);if(formElement.isConnected)ctx.close();ctx.toast('Saved to your family. Other devices will refresh.');
      }catch(error){const target=formElement.querySelector('#cloud-command-error');if(target&&formElement.isConnected&&generation===ctx.generation())target.textContent=error.message;}
      finally{busy=false;button.disabled=false;}
    };
  }
  function work(preset){
    const p=preset||['','gig',100,''];
    form('Add work',`<label for="cloud-type">Type</label><select id="cloud-type"><option value="gig" ${p[1]==='gig'?'selected':''}>Paid gig</option><option value="responsibility" ${p[1]==='responsibility'?'selected':''}>Responsibility · unpaid</option></select>${field('cloud-title','Title','text',p[0],'required maxlength="100"')}<label for="cloud-instructions">Instructions</label><textarea id="cloud-instructions" maxlength="1000">${esc(p[3])}</textarea><label for="cloud-child">Child</label><select id="cloud-child">${options()}<option value="">Open to any child</option></select>${field('cloud-reward','Gig reward (family currency)','number',(p[2]/100).toFixed(2),'min="0.01" step="0.01"')}${field('cloud-due','Due date','date',localDate(),'required')}<p class="subtle">One-time work. Responsibilities never pay money.</p>`,'Add work','createWork',()=>({type:$('#cloud-type').value,title:$('#cloud-title').value,instructions:$('#cloud-instructions').value,childId:$('#cloud-child').value,reward:$('#cloud-type').value==='gig'?cents($('#cloud-reward').value):0,due:$('#cloud-due').value}));
    const update=()=>{$('#cloud-reward').disabled=$('#cloud-type').value!=='gig';};$('#cloud-type').onchange=update;update();
  }
  function presetPicker(){
    ctx.modal('A little inspiration',`<p>Choose a preset, then edit it before adding it. All paid presets are under 3 in your family’s currency.</p><div class="presets-scroll">${presetSections(esc,ctx.money,'data-cloud-preset')}</div><button class="button-full" id="cloud-presets-done">Done!</button><p class="error" id="cloud-command-error" role="alert"></p>`);
    document.querySelectorAll('[data-cloud-preset]').forEach(b=>b.onclick=()=>work(presets[Number(b.dataset.cloudPreset)]));
    const key=uid();$('#cloud-presets-done').onclick=async e=>{e.target.disabled=true;try{ctx.accept(await sendCloudCommand(ctx.state(),'dismissPresets',{},key,null));ctx.close();ctx.toast('You can reopen this list with Show presets in Tasks.');}catch(err){$('#cloud-command-error').textContent=err.message;e.target.disabled=false;}};
  }
  const actions={
    'remove-child':id=>form('Remove child?',`<p>Remove ${esc(ctx.state().children.find(c=>c.id===id)?.name)} from the family on all connected devices? Past records stay in your family backup. Settle their balances, earnings, open work and cart first. At least one child must remain.</p><label class="check"><input type="checkbox" required>I want to remove this child.</label>`,'Remove child','removeChild',()=>({childId:id}),{sensitive:true}),
    'cloud-pin':()=>ctx.setupPin(true),'create-work':()=>work(),presets:presetPicker,
    start:id=>form('Start this work?',`<p>${esc(ctx.state().work.find(w=>w.id===id)?.title)}</p>`,'Start work','start',()=>({id})),
    submit:id=>{
      const work=ctx.state().work.find(w=>w.id===id);
      if(work.proofRequired){ctx.modal('Proof photo needed','<p>This task needs a private proof photo. Please submit it from the Mac app for now. Phone photo uploads are not ready.</p>');return;}
      form('Ready for a parent?',`${work.checklist.map(s=>`<label class="check"><input type="checkbox" required>${esc(s)}</label>`).join('')}<label for="cloud-note">A short note</label><textarea id="cloud-note" maxlength="1000"></textarea><label class="check"><input type="checkbox" required>I checked my work.</label>`,'Send to my grown-up','submit',()=>({id,note:$('#cloud-note').value,checklistConfirmed:true}));
    },
    review:id=>{const w=ctx.state().work.find(w=>w.id===id);form('Review work',`<h3>${esc(w.title)}</h3><p class="note">${esc(w.note||'No note added.')}</p><p>${w.type==='gig'?ctx.money(w.acceptedReward)+' pending after approval.':'Unpaid responsibility. No money is added.'}</p><label for="cloud-decision">Decision</label><select id="cloud-decision"><option value="approved">Approve</option><option value="redoRequested">Request redo</option><option value="rejected">Reject</option></select><label for="cloud-reason">Kind reason (required for redo or rejection)</label><textarea id="cloud-reason" maxlength="1000"></textarea>`,'Save review','review',()=>({id,decision:$('#cloud-decision').value,reason:$('#cloud-reason').value}));},
    'edit-child':id=>{const c=ctx.state().children.find(c=>c.id===id);form('Edit child & money split',`${field('cloud-name','Name','text',c.name,'required maxlength="40"')}<fieldset class="split-group"><legend>Money split · must total 100%</legend><div class="split">${['spend','save','give'].map(j=>`<div class="split-field">${field('cloud-'+j,j+' %','number',c.split[j],'required min="0" max="100" step="1"')}</div>`).join('')}</div><p id="cloud-split-total" aria-live="polite"></p></fieldset>`,'Save settings','editChild',()=>({childId:id,name:$('#cloud-name').value,split:Object.fromEntries(['spend','save','give'].map(j=>[j,Number($('#cloud-'+j).value)]))}));const validate=()=>{const total=['spend','save','give'].reduce((n,j)=>n+Number($('#cloud-'+j).value),0);$('#cloud-split-total').textContent=`Total: ${total}%${total===100?'':' — must equal 100%'}`;$('#cloud-command button[type="submit"]').disabled=total!==100;};['spend','save','give'].forEach(j=>$('#cloud-'+j).oninput=validate);validate();},
    goal:()=>form('Something to save for',`<label for="cloud-child">Child</label><select id="cloud-child">${options()}</select>${field('cloud-title','Goal name','text','','required maxlength="80"')}${field('cloud-target','Target (family currency)','number','','min="0.01" step="0.01" required')}<p>New Save deposits go to this featured goal. Existing savings stay where they are.</p>`,'Create goal','addGoal',()=>({childId:$('#cloud-child').value,title:$('#cloud-title').value,target:cents($('#cloud-target').value)})),
    purchase:()=>form('Record a purchase or withdrawal',`<p>This records money handled outside PocketCrew. It does not buy anything.</p><label for="cloud-child">Child</label><select id="cloud-child">${options()}</select><label for="cloud-jar">Jar</label><select id="cloud-jar"><option value="spend">Spend · purchase</option><option value="save">Save · withdrawal</option><option value="give">Give · gift</option></select>${field('cloud-amount','Amount (family currency)','number','','min="0.01" step="0.01" required')}${field('cloud-reason','What was it for?','text','','required maxlength="150"')}`,'Confirm deduction','record',()=>({childId:$('#cloud-child').value,jar:$('#cloud-jar').value,amount:cents($('#cloud-amount').value),reason:$('#cloud-reason').value}),{sensitive:true}),
    payday:()=>{
      const s=ctx.state(),early=new Date(s.nextPaydayAt)>new Date();
      form(early?'Confirm early payday':'Confirm payday',s.children.map(c=>{const total=pending(s,c.id),a=allocation(total,c.split),rule=s.matchRules.find(r=>r.childId===c.id&&r.enabled),match=rule?Math.min(Math.floor(a.save*rule.percent/100),rule.capCents??Infinity):0;return `<h3>${esc(c.name)} · ${ctx.money(total)}</h3><p>Spend ${ctx.money(a.spend)} · Save ${ctx.money(a.save)} · Give ${ctx.money(a.give)}</p><p>Parent savings match: ${ctx.money(match)} · Save total: ${ctx.money(a.save+match)}</p>`;}).join('')+'<p>Only gigs a grown-up has approved are included. Any configured savings match is added to Save. No real funds move.</p><label class="check"><input type="checkbox" required>I confirm this '+(early?'early ':'')+'payday.</label>','Pay now','payday',()=>({confirmed:true,earlyConfirmed:early}),{sensitive:true});
    },
    schedule:()=>form('Payday schedule',`<label for="cloud-frequency">Frequency</label><select id="cloud-frequency">${[['weekly','Weekly'],['biweekly','Every two weeks'],['twiceMonthly','Twice monthly (1st and 15th)'],['monthly','Monthly'],['custom','Custom']].map(([v,n])=>`<option value="${v}" ${ctx.state().frequency===v?'selected':''}>${n}</option>`).join('')}</select><div id="custom-days-row"><label for="cloud-custom-days">Every</label><input id="cloud-custom-days" type="number" min="1" max="365" step="1" value="${ctx.state().customDays||7}"><span>days (Custom only)</span></div>${field('cloud-date','Next payday','date',ctx.state().nextPayday,'required')}`,'Save schedule','schedule',()=>({date:$('#cloud-date').value,frequency:$('#cloud-frequency').value,customDays:$('#cloud-frequency').value==='custom'?Number($('#cloud-custom-days').value):null}))
  };
  document.addEventListener('click',event=>{
    if(!ctx.state()?.cloud)return;
    const b=event.target.closest('button[data-act]');if(!b||!actions[b.dataset.act])return;
    event.preventDefault();event.stopImmediatePropagation();
    if(ctx.actor?.()&&ctx.actor()!=='parent'&&!ctx.access()){ctx.toast('Return to Parent to make changes, or use the child’s own connection.');return;}
    if(ctx.access()&&!['start','submit'].includes(b.dataset.act))return;
    actions[b.dataset.act](b.dataset.id);
  },true);
}
