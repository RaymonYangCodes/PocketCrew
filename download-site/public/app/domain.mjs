export const uid = () => crypto.randomUUID();
export const jars = ['spend', 'save', 'give'];
export const presets = [
  ["Dust reachable surfaces","gig",100,"Use a soft cloth on reachable surfaces; leave fragile items alone.","Household"],
  ["Match the socks","gig",75,"Pair clean socks and put them in the right drawers.","Household"],
  ["Wipe door handles","gig",100,"Use a parent-approved damp cloth on reachable handles.","Household"],
  ["Organize board games","gig",150,"Match pieces to boxes and stack the games neatly.","Household"],
  ["Read and summarize a chapter","gig",150,"Choose a book and share three things you learned.","Academic"],
  ["Practice math","gig",100,"Spend 15 minutes on a parent-approved practice sheet and review mistakes.","Academic"],
  ["Practice spelling","gig",100,"Practice ten words and use each in a sentence.","Academic"],
  ["Make a science journal page","gig",200,"Observe something safe in nature, draw it, and describe what you notice.","Academic"],
  ["Water the garden","gig",100,"Ask which plants need watering and use the agreed amount.","Outdoors"],
  ["Sweep the patio","gig",150,"Sweep the agreed area and collect the leaves and dust.","Outdoors"],
  ["Collect outdoor toys","gig",100,"Collect your toys from the yard and put them away.","Outdoors"],
  ["Plant some seeds","gig",200,"With a grown-up, plant seeds, label them, and water gently.","Outdoors"],
  ["Take a family walk","gig",100,"Take a comfortable 15-minute walk with your family; stop if you feel unwell.","Exercise"],
  ["Try a gentle stretch break","gig",75,"Choose comfortable stretches with a grown-up. Never stretch through pain.","Exercise"],
  ["Have a dance break","gig",100,"Move to three favorite songs in a clear, safe space.","Exercise"],
  ["Practice throwing and catching","gig",100,"Use a soft ball in a safe space and practice with a partner.","Exercise"],
  ["Write a thank-you card","gig",100,"Write and decorate a thoughtful card for someone who helped you.","Creative"],
  ["Draw a short comic","gig",150,"Make a four-panel comic with a beginning, middle, and ending.","Creative"],
  ["Sort the pet toys","gig",100,"Sort safe toys and ask a grown-up to check damaged ones.","Pet care"],
  ["Help brush the pet","gig",150,"With a grown-up, gently brush a comfortable pet using the right brush.","Pet care"],
  ['Make the bed','responsibility',0,'Straighten sheets and arrange pillows.'],
  ['Pack school bag','responsibility',0,'Pack homework, supplies and water for tomorrow.'],
  ['Feed the dog','responsibility',0,'Check the right portion with your parent; refill water.'],
  ['Set the table','responsibility',0,'Set out plates, cutlery and napkins.'],
  ['Tidy your room','responsibility',0,'Put clothes and toys in their places.'],
  ['Water the plants','responsibility',0,'Ask which plants need water today.'],
  ['Wash the car','gig',250,'Wash and rinse with a grown-up.'],
  ['Organize the pantry','gig',200,'Group items and wipe accessible shelves.'],
  ['Vacuum the living room','gig',100,'Clear the floor, then vacuum carefully.'],
  ['Rake leaves','gig',250,'Rake the agreed area and bag the leaves.'],
  ['Help cook dinner','gig',200,'Help plan and prepare dinner with a grown-up.'],
  ['Fold laundry','gig',150,'Fold clean clothes and sort by person.'],
  ['Sort the books','gig',150,'Organize books and dust the shelf.'],
  ['Clean the bikes','gig',200,'Wipe frames and check with a parent when done.']
].map(p=>p.length===5?p:[...p,/school/i.test(p[0])?'Academic':/dog/i.test(p[0])?'Pet care':/plants|car|leaves|bikes/i.test(p[0])?'Outdoors':'Household']);
export function cents(value) {
  if (!/^\d+(\.\d{1,2})?$/.test(String(value))) throw Error('Use a positive amount with up to two decimal places.');
  const [whole, fraction=''] = String(value).split('.');
  const result = Number(whole)*100 + Number(fraction.padEnd(2,'0'));
  if (!Number.isSafeInteger(result) || result > 10000000) throw Error('Choose a smaller amount.');
  return result;
}
export function validateSplit(split) {
  if (!jars.every(j => Number.isInteger(split[j]) && split[j]>=0 && split[j]<=100) || jars.reduce((n,j)=>n+split[j],0)!==100) throw Error('Spend + Save + Give must equal 100%.');
}
export function allocation(amount, split) {
  validateSplit(split);
  if (!Number.isSafeInteger(amount) || amount<0) throw Error('Invalid earnings.');
  const save=Math.floor(amount*split.save/100), give=Math.floor(amount*split.give/100);
  return {spend:amount-save-give, save, give};
}
export const balance = (s, childId, jar) => s.ledger.filter(t=>t.childId===childId && t.jar===jar).reduce((n,t)=>n+t.amount,0);
export const pending = (s, childId) => s.earnings.filter(e=>e.childId===childId && !e.paydayId).reduce((n,e)=>n+e.amount,0);
const guardian = actor => {if(actor!=='parent') throw Error('A parent needs to do this.');};
export function removeChild(s, actor, id) {
  guardian(actor);
  const c=s.children.find(c=>c.id===id);
  if(!c)throw Error('This child has already been removed.');
  if(s.children.length<=1)throw Error('Keep at least one child in the family.');
  if(jars.some(j=>balance(s,id,j)!==0)||pending(s,id)>0)throw Error('Settle this child’s jar balances and pending earnings first.');
  if(s.work.some(w=>w.childId===id&&!['approved','paid','rejected'].includes(w.status)))throw Error('Finish or review this child’s open work first.');
  if((s.shoppingEntries||[]).some(e=>e.childId===id&&e.status==='awaitingApproval'))throw Error('Review this child’s cart first.');
  s.children=s.children.filter(c=>c.id!==id);
  s.archivedChildren=[...(s.archivedChildren||[]),{...c,removedAt:new Date().toISOString()}];
  audit(s,actor,'Removed child: '+c.name,id);
}
function audit(s, actor, action, entityId) { s.audit.push({id:uid(),at:new Date().toISOString(),actor,action,entityId}); }
export function createWork(s, actor, data) {
  guardian(actor);
  if (!data.title.trim() || !['gig','responsibility'].includes(data.type)) throw Error('Add a name and work type.');
  if (data.childId && !s.children.some(c=>c.id===data.childId)) throw Error('Choose a child.');
  if (!Number.isSafeInteger(data.reward) || data.reward<0 || (data.type==='gig' && data.reward===0)) throw Error('A paid gig needs a positive reward.');
  const work={...data,id:uid(),title:data.title.trim(),reward:data.type==='gig'?data.reward:0,status:data.childId?'assigned':'available',note:'',reason:'',createdAt:new Date().toISOString()};
  s.work.push(work);audit(s,actor,'Created work',work.id);return work;
}
export function startWork(s, actor, id) {
  const w=s.work.find(w=>w.id===id);
  if (!w || actor==='parent' || !s.children.some(c=>c.id===actor) || (w.childId && w.childId!==actor) || !['available','assigned','redoRequested'].includes(w.status)) throw Error('This work is not available to this profile.');
  w.childId=actor;w.status='inProgress';w.acceptedReward ??=w.reward;
}
export function submitWork(s, actor, id, note) {
  const w=s.work.find(w=>w.id===id);
  if (!w || actor==='parent' || w.childId!==actor || !['inProgress','redoRequested'].includes(w.status)) throw Error('Start your work before submitting it.');
  w.note=note.trim();w.status='awaitingApproval';w.submittedAt=new Date().toISOString();
}
export function review(s, actor, id, decision, reason='') {
  guardian(actor);const w=s.work.find(w=>w.id===id);
  if (!w || w.status!=='awaitingApproval') throw Error('This submission has already been reviewed.');
  if (!['approved','redoRequested','rejected'].includes(decision)) throw Error('Choose a review decision.');
  if (decision!=='approved' && !reason.trim()) throw Error('Add a kind, specific reason.');
  w.status=decision;w.reason=reason.trim();
  if (decision==='approved' && w.type==='gig' && !s.earnings.some(e=>e.workId===id)) s.earnings.push({id:uid(),workId:id,childId:w.childId,amount:w.acceptedReward??w.reward,paydayId:null});
  audit(s,actor,decision,id);
}
export function runPayday(s, actor, key) {
  guardian(actor);const old=s.paydays.find(p=>p.id===key);if(old)return old;
  const earnings=s.earnings.filter(e=>!e.paydayId);if(!earnings.length)throw Error('No approved earnings are ready yet.');
  const interval=s.frequency==='custom'?s.customDays:7;
  if(!Number.isInteger(interval)||interval<1||interval>365)throw Error('Choose a whole number from 1 to 365 days.');
  const at=new Date().toISOString(),lines=s.children.map(c=>({childId:c.id,gross:earnings.filter(e=>e.childId===c.id).reduce((n,e)=>n+e.amount,0),split:c.split})).filter(l=>l.gross>0).map(l=>({...l,amounts:allocation(l.gross,l.split)}));
  const payday={id:key,at,lines,total:lines.reduce((n,l)=>n+l.gross,0)};
  for(const line of lines)for(const jar of jars){
    if(line.amounts[jar])s.ledger.push({id:uid(),childId:line.childId,jar,amount:line.amounts[jar],description:'Payday',category:'payday',paydayId:key,at});
    if(jar==='save'){const goal=s.goals.find(g=>g.childId===line.childId && g.featured && g.saved<g.target);if(goal)goal.saved=Math.min(goal.target,goal.saved+line.amounts.save);}
  }
  earnings.forEach(e=>{e.paydayId=key;const w=s.work.find(w=>w.id===e.workId);if(w)w.status='paid';});
  s.paydays.push(payday);
  const next=new Date(s.nextPayday+'T12:00:00');do{next.setDate(next.getDate()+interval);}while(next<=new Date());s.nextPayday=localDate(next);
  audit(s,actor,'Ran payday',key);return payday;
}
export function purchase(s,actor,childId,jar,amount,reason) {
  guardian(actor);
  if(!s.children.some(c=>c.id===childId)||!jars.includes(jar)||!Number.isSafeInteger(amount)||amount<=0||!reason.trim())throw Error('Choose a child, amount and reason.');
  if(balance(s,childId,jar)<amount)throw Error(`There isn’t enough in ${jar}. Nothing has been deducted.`);
  const id=uid();s.ledger.push({id,childId,jar,amount:-amount,description:reason.trim(),category:jar,at:new Date().toISOString()});
  if(jar==='save'){let remaining=amount;for(const g of s.goals.filter(g=>g.childId===childId)){const reduction=Math.min(g.saved,remaining);g.saved-=reduction;remaining-=reduction;}}
  audit(s,actor,'Recorded '+jar,id);
}
export function localDate(d=new Date()){return `${d.getFullYear()}-${String(d.getMonth()+1).padStart(2,'0')}-${String(d.getDate()).padStart(2,'0')}`;}
export function fresh(name='Our family') {
  const friday=new Date();friday.setDate(friday.getDate()+((5-friday.getDay()+7)%7||7));
  return {version:1,id:uid(),revision:0,name,children:[],work:[],earnings:[],paydays:[],ledger:[],goals:[],audit:[],nextPayday:localDate(friday),presetsDone:false,demo:false};
}
export function demo() {
  const s=fresh('The Parkers');s.demo=true;
  s.children=[{id:'jordan',name:'Jordan',split:{spend:50,save:40,give:10}},{id:'riley',name:'Riley',split:{spend:60,save:30,give:10}}];
  s.goals=[{id:uid(),childId:'jordan',title:'Headphones',target:14000,saved:8400,featured:true},{id:uid(),childId:'riley',title:'Scooter helmet',target:6000,saved:2400,featured:true}];
  s.children.forEach((c,i)=>jars.forEach((jar,j)=>s.ledger.push({id:uid(),childId:c.id,jar,amount:[[1800,8400,600],[950,2400,300]][i][j],description:'Demo starting balance',category:'adjustment',at:new Date(Date.now()-14*86400000).toISOString()})));
  const w=presets.slice(0,3).concat(presets.slice(6,11)).map((p,i)=>createWork(s,'parent',{title:p[0],type:p[1],reward:p[2],instructions:p[3],childId:i===7?'':s.children[i%2].id,due:localDate()}));
  startWork(s,w[3].childId,w[3].id);submitWork(s,w[3].childId,w[3].id,'All clean! I put the supplies away.');
  startWork(s,w[4].childId,w[4].id);submitWork(s,w[4].childId,w[4].id,'The shelves are tidy.');review(s,'parent',w[4].id,'approved');
  startWork(s,w[5].childId,w[5].id);submitWork(s,w[5].childId,w[5].id,'Finished.');review(s,'parent',w[5].id,'redoRequested','Please get the little area beside the sofa too.');
  startWork(s,w[6].childId,w[6].id);return s;
}
