import {uid,purchase} from './domain.mjs';

export function photoURL(value){
  try{const u=new URL(value);return u.protocol==='https:'&&!u.username&&!u.password&&!u.port&&['gstatic.com','googleusercontent.com','serpapi.com'].some(h=>u.hostname===h||u.hostname.endsWith('.'+h))?u.href:null;}catch{return null;}
}
export function storeURL(value){
  try{const u=new URL(value);return u.protocol==='https:'&&!u.username&&!u.password&&['www.google.com','google.com'].includes(u.hostname)?u.href:null;}catch{return null;}
}
export function applyLocalShopping(s,actor,action,d){
  const guardian=actor==='parent';
  if(!actor||(!guardian&&!s.children.some(c=>c.id===actor)))throw Error('Unlock your profile first.');
  if(!guardian&&!['add','cart','remove','goal','featureGoal','archiveGoal'].includes(action))throw Error('A parent needs to do this.');
  s.shoppingEntries??=[];
  const entry=s.shoppingEntries.find(e=>e.id===d.id),goal=s.goals.find(g=>g.id===d.id);
  const kid=entry?.childId||d.childId;
  const stamp=new Date().toISOString();
  if(action==='completeGoal'){
    if(!goal||(goal.status&&goal.status!=='active'))throw Error('Choose an active goal that has not already been completed.');
    if(!Number.isSafeInteger(goal.target)||goal.target<=0||d.expectedPrice!==goal.target)throw Error('The target changed. Review the goal again.');
    purchase(s,actor,goal.childId,'spend',goal.target,'Goal completed · '+goal.title);
    goal.status='completed';goal.featured=false;return;
  }
  if(action==='archiveGoal'){
    if(!goal||!s.children.some(c=>c.id===goal.childId)||(!guardian&&goal.childId!==actor))throw Error('Choose your own goal.');
    if(goal.status==='archived')throw Error('This goal was already removed.');
    goal.status='archived';goal.featured=false;return;
  }
  if(action==='featureGoal'){
    if(!goal||!s.children.some(c=>c.id===goal.childId)||(!guardian&&goal.childId!==actor))throw Error('Choose your own goal.');
    if((goal.status&&goal.status!=='active')||goal.saved>=goal.target)throw Error('Choose an approved, active goal.');
    s.goals.filter(g=>g.childId===goal.childId).forEach(g=>{g.featured=g.id===goal.id;});return;
  }
  if(action==='reviewGoal'){
    if(!goal||goal.status!=='proposed'||!['active','archived'].includes(d.decision))throw Error('This goal has already been reviewed.');
    goal.status=d.decision;goal.featured=d.decision==='active'&&!s.goals.some(g=>g.childId===goal.childId&&g.featured);return;
  }
  if(!s.children.some(c=>c.id===kid)||(!guardian&&kid!==actor))throw Error('You can only change your own list.');
  if(d.id&&(!entry||!['wishlist','awaitingApproval'].includes(entry.status)))throw Error('Only wishlist and pending cart items can be changed.');
  const product=structuredClone(entry?.product||d.product);
  const price=n=>{if(!Number.isSafeInteger(n)||n<=0||n>100000000)throw Error('Enter a positive price with at most two decimal places.');return n;};
  if(['add','goal'].includes(action)){
    if(!product?.id||!product.title||product.title.length>240)throw Error('Choose an item first.');price(product.priceCents);
    if(product.currencyCode&&product.currencyCode!==(s.currency||'USD'))throw Error('The item currency must match your family.');
  }
  if(action==='add'){
    if(!['wishlist','awaitingApproval'].includes(d.destination))throw Error('Choose Wishlist or Cart.');
    if(s.shoppingEntries.some(e=>e.childId===kid&&e.product.id===product.id&&['wishlist','awaitingApproval'].includes(e.status)))throw Error('This item is already on your list.');
    s.shoppingEntries.push({id:uid(),childId:kid,product,status:d.destination,createdAt:stamp,updatedAt:stamp});
  }else if(action==='goal'){
    price(d.target);if(!d.title?.trim())throw Error('Give your goal a name.');
    if(s.goals.some(g=>g.childId===kid&&g.shoppingProduct?.id===product.id&&!['archived','completed'].includes(g.status)))throw Error('This item already has a goal.');
    s.goals.push({id:uid(),childId:kid,title:d.title,target:d.target,saved:0,icon:'🎯',targetDate:d.targetDate||null,shoppingProduct:product,status:guardian?'active':'proposed',featured:guardian&&!s.goals.some(g=>g.childId===kid&&g.featured)});
  }else if(action==='price'){
    price(d.priceCents);if(!d.reason?.trim())throw Error('Add a reason for the price change.');
    const before=entry.product.priceCents;entry.product.priceCents=d.priceCents;entry.parentNote='Price set by parent: '+d.reason;
    s.audit??=[];s.audit.push({id:uid(),action:'shopping.price',at:stamp,entryId:entry.id,before,after:d.priceCents,reason:d.reason});
  }else if(action==='cart'){
    if(entry.status!=='wishlist')throw Error('This item is already in the cart.');entry.status='awaitingApproval';
  }else if(action==='approve'){
    if(entry.status!=='awaitingApproval')throw Error('Request a purchase first.');
    if(d.expectedPrice!==product.priceCents)throw Error('The price changed. Review the new price before approving.');
    purchase(s,actor,kid,'spend',price(product.priceCents),'Shopping purchase · '+product.title);
    entry.status='purchased';entry.resolvedAt=stamp;
  }else if(action==='gift'){entry.status='gifted';entry.resolvedAt=stamp;entry.parentNote='Given by a parent — no Spend deducted.';
  }else if(action==='decline'){if(!d.reason?.trim())throw Error('Add a kind reason.');entry.status='declined';entry.parentNote=d.reason;entry.resolvedAt=stamp;
  }else if(action==='remove'){entry.status='removed';entry.resolvedAt=stamp;
  }else throw Error('Unsupported action.');
  if(entry)entry.updatedAt=stamp;
}

export const shoppingSamples=[
  {id:'sample-headphones',title:'Colorful headphones',priceCents:2999,merchant:'PocketCrew demo'},
  {id:'sample-art',title:'Drawing supplies',priceCents:1299,merchant:'PocketCrew demo'},
  {id:'sample-helmet',title:'Scooter helmet',priceCents:2499,merchant:'PocketCrew demo'}
].map(p=>({...p,source:'pocketCrew',detail:'Sample idea, not a store listing',category:'Demo',symbol:'shippingbox.fill',currencyCode:'USD'}));
