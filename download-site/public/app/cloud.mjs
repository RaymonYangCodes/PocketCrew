// Public project configuration only. Never put a service-role key here.
const URL='https://bvfzqfeyxyjycmkpifgz.supabase.co';
const KEY='sb_publishable_rSy5ZLM5o5IQnmvyJoMyhw_Ecl_Zq_t';
const CALLBACK='https://pocket-crew.vercel.app/app/';
let session=null;
const SESSION_KEY='pocketcrew.parent-session.v1';
let refreshInFlight=null;
function remember(value){
  localStorage.setItem(SESSION_KEY,JSON.stringify(value));
  session=value;
}
export function restoreSavedSession(){
  const saved=JSON.parse(localStorage.getItem(SESSION_KEY)||'null');
  if(!saved?.access_token||!saved?.refresh_token||!saved?.user?.id)return false;
  session=saved;return true;
}
async function refreshSession(){
  if(!refreshInFlight){
    const previous=session;
    refreshInFlight=request('/auth/v1/token?grant_type=refresh_token',{refresh_token:previous.refresh_token})
      .then(next=>{if(session===previous)remember(next);})
      .finally(()=>{refreshInFlight=null;});
  }
  await refreshInFlight;
}
export const cloudUser=()=>session?.user??null;
async function request(path,body,method='POST') {
  if(session&&!path.startsWith('/auth/')&&session.expires_at*1000<Date.now()+60000){
    await refreshSession();
  }
  const response=await fetch(URL+path,{method,headers:{apikey:KEY,...(session?{Authorization:'Bearer '+session.access_token}:{}),'Content-Type':'application/json'},...(body===undefined?{}:{body:JSON.stringify(body)})});
  const text=await response.text();
  const data=text?JSON.parse(text):{};
  if(!response.ok)throw Error(data.msg||data.message||data.error_description||data.error||'Could not connect. Please try again.');
  if(data.access_token&&!data.expires_at)data.expires_at=Math.floor(Date.now()/1000)+(data.expires_in||3600);
  return data;
}
export async function googleSignIn(){
  const bytes=crypto.getRandomValues(new Uint8Array(48));
  const verifier=Array.from(bytes,b=>b.toString(16).padStart(2,'0')).join('');
  const digest=await crypto.subtle.digest('SHA-256',new TextEncoder().encode(verifier));
  const challenge=btoa(String.fromCharCode(...new Uint8Array(digest))).replace(/\+/g,'-').replace(/\//g,'_').replace(/=+$/,'');
  sessionStorage.setItem('pocketcrew.oauth',JSON.stringify({verifier,at:Date.now()}));
  const query=new URLSearchParams({provider:'google',redirect_to:CALLBACK,code_challenge:challenge,code_challenge_method:'s256',scopes:'openid email profile'});
  location.assign(URL+'/auth/v1/authorize?'+query);
}
export async function completeSignIn(){
  const query=new URLSearchParams(location.search);
  if(query.has('error')){history.replaceState(null,'','/app/');throw Error('Sign-in was not completed. Please try again.');}
  if(!query.has('code'))return false;
  const pending=JSON.parse(sessionStorage.getItem('pocketcrew.oauth')||'null');
  const code=query.get('code');history.replaceState(null,'','/app/');
  sessionStorage.removeItem('pocketcrew.oauth');
  if(!pending||Date.now()-pending.at>600000)throw Error('This sign-in expired. Start again on this device.');
  remember(await request('/auth/v1/token?grant_type=pkce',{auth_code:code,code_verifier:pending.verifier}));
  return true;
}
export async function emailSignIn(email,password){remember(await request('/auth/v1/token?grant_type=password',{email,password}));}
export async function cloudSignOut(){const old=session;session=null;localStorage.removeItem(SESSION_KEY);if(old)await fetch(URL+'/auth/v1/logout?scope=local',{method:'POST',headers:{apikey:KEY,Authorization:'Bearer '+old.access_token}});}
// A child's capability is never sent with a parent's session or stored on disk.
export async function readChildConnection(token,pin){
  if(!/^[0-9a-f]{64}$/.test(token)||!/^\d{6,8}$/.test(pin))throw Error('Use your private invitation and its 6–8 digit passcode.');
  let response;
  try{response=await fetch(URL+'/rest/v1/rpc/read_child_connection',{method:'POST',cache:'no-store',headers:{apikey:KEY,'Content-Type':'application/json'},body:JSON.stringify({p_token:token,p_pin:pin})});}
  catch{throw Error('Could not reach your family. Check your connection and try again in Safari or Chrome. No profile was opened.');}
  const data=await response.json();
  if(!response.ok||data.error)throw Error(data.error||'Could not open this child profile. Ask a parent for a new invitation.');
  if(data.state?.children?.length!==1||data.state.children[0].id.toLowerCase()!==data.child_id?.toLowerCase())throw Error('This profile could not be safely opened.');
  return data;
}
export async function sendCloudCommand(state,action,data,commandId,childAccess,command='family_work_command'){
  if(!['family_work_command','family_shopping_command'].includes(command))throw Error('Unsupported command.');
  const body={p_family_id:state.id,p_revision:state.revision,p_command_id:commandId,p_action:action,p_data:data};
  let row;
  if(childAccess){
    body.p_child_token=childAccess.token;body.p_child_pin=childAccess.pin;
    const response=await fetch(URL+'/rest/v1/rpc/'+command,{method:'POST',cache:'no-store',headers:{apikey:KEY,'Content-Type':'application/json'},body:JSON.stringify(body)});
    row=await response.json();if(!response.ok)throw Error(row.message||'Could not save. Refresh and try again.');
    if(!row.error&&(row.state?.children?.length!==1||row.state.children[0].id.toLowerCase()!==row.child_id?.toLowerCase()))throw Error('This profile could not be safely opened.');
  }else row=await rpc(command,body);
  if(row.error)throw Error(row.error);
  return phoneView(row);
}
export function invitationToken(value){
  const raw=value.trim();
  const token=raw.includes('://')?new URLSearchParams(new globalThis.URL(raw).hash.slice(1)).get('child'):raw;
  if(!/^[0-9a-f]{64}$/.test(token||''))throw Error('Paste the complete child invitation link from your parent.');
  return token;
}
export async function searchShopping(query,currency,childAccess,publicSearch=false){
  const body={query,currency:currency||'USD'};let response;
  if(publicSearch){
    response=await fetch(URL+'/functions/v1/search-shopping-products',{method:'POST',cache:'no-store',headers:{apikey:KEY,'Content-Type':'application/json'},body:JSON.stringify({...body,publicSearch:true})});
    const data=await response.json();if(!response.ok)throw Error(data.error||'Live search is unavailable. Please try again.');return data.items||[];
  }
  if(childAccess){
    response=await fetch(URL+'/functions/v1/search-shopping-products',{method:'POST',cache:'no-store',headers:{apikey:KEY,'Content-Type':'application/json'},body:JSON.stringify({...body,childToken:childAccess.token,childPin:childAccess.pin})});
    const data=await response.json();if(!response.ok)throw Error(data.error||'Search is unavailable. Please try again.');return data.items||[];
  }
  const data=await request('/functions/v1/search-shopping-products',body);return data.items||[];
}
export async function rpc(name,body){
  if(session&&session.expires_at*1000<Date.now()+60000)await refreshSession();
  return request('/rest/v1/rpc/'+name,body);
}
export async function loadCloudFamily(){
  if(!session)throw Error('Please sign in as a parent.');
  const memberships=await request('/rest/v1/family_guardians?select=family_id&status=eq.active&user_id=eq.'+session.user.id,undefined,'GET');
  if(!memberships.length)return null;
  const rows=await request('/rest/v1/family_snapshots?select=family_id,revision,state&family_id=eq.'+memberships[0].family_id,undefined,'GET');
  if(!rows.length)throw Error('Your family record could not be opened.');
  return rows[0];
}
export async function acceptFamilyInvite(token){await rpc('accept_family_invite',{p_token:token.trim()});return loadCloudFamily();}

// Translate for display only: the native snapshot remains the authoritative record.
// Unknown/native-only fields are never rewritten by this read-only adapter.
export function phoneView(row){
  // Swift UUID encoding is uppercase; Postgres uses lowercase. Normalize only UUID
  // values in this display copy, never edit the authoritative native snapshot.
  const n=JSON.parse(JSON.stringify(row.state),(_,v)=>typeof v==='string'&&/^[0-9a-f]{8}(-[0-9a-f]{4}){3}-[0-9a-f]{12}$/i.test(v)?v.toLowerCase():v);
  if(!n?.family||!Array.isArray(n.assignments))throw Error('This family format is not supported yet.');
  const day=value=>{const parts=new Intl.DateTimeFormat('en-US',{timeZone:n.family.timezone,year:'numeric',month:'2-digit',day:'2-digit'}).formatToParts(new Date(value));const part=t=>parts.find(p=>p.type===t).value;return `${part('year')}-${part('month')}-${part('day')}`;};
  const children=n.children.filter(c=>c.status==='active').map(c=>{
    const rule=n.splits.find(s=>s.childId===c.id);
    return {id:c.id,name:c.name,split:{spend:rule?.spendPercent??50,save:rule?.savePercent??40,give:rule?.givePercent??10}};
  });
  return {version:1,id:n.family.id,revision:row.revision,name:n.family.name,currency:n.family.currency,locale:n.family.locale,cloud:true,demo:false,presetsDone:n.family.workPresetsDismissed,
    matchRules:n.matchRules||[],nextPaydayAt:n.schedule.nextPaydayAt,children,nextPayday:day(n.schedule.nextPaydayAt),frequency:n.schedule.frequency||'weekly',customDays:n.schedule.customDays||null,
    work:n.assignments.map(a=>{const w=n.workItems.find(w=>w.id===a.workItemId),sub=n.submissions.filter(s=>s.assignmentId===a.id).at(-1),decision=sub&&n.decisions.filter(d=>d.submissionId===sub.id).at(-1);return {id:a.id,childId:a.childId||'',type:w?.type??'responsibility',title:w?.title??'Work',instructions:w?.instructions??'',proofRequired:w?.proofRequired,checklist:w?.checklist||[],reward:a.rewardSnapshotCents,acceptedReward:a.rewardSnapshotCents,status:a.status,due:day(a.dueAt),note:sub?.note??'',reason:decision?.reason??''};}),
    earnings:n.earnings.filter(e=>e.status!=='reversed').map(e=>({id:e.id,childId:e.childId,workId:e.assignmentId,amount:e.amountCents,paydayId:e.paydayId})),
    ledger:n.ledger.map(t=>({id:t.id,childId:t.childId,jar:t.jar,amount:t.amountCents,description:t.description,category:t.category,at:t.createdAt,paydayId:t.paydayId})),
    shoppingEntries:n.shoppingEntries||[],
    goals:n.goals.filter(g=>g.status!=='archived').map(g=>({id:g.id,childId:g.childId,title:g.title,target:g.targetCents,saved:g.allocatedCents,featured:g.featured,status:g.status,icon:g.icon,targetDate:g.targetDate,shoppingProduct:g.shoppingProduct})),
    paydays:n.paydays.map(p=>({id:p.id,at:p.processedAt,total:p.totalEarningsCents+p.totalMatchCents,lines:n.paydayLines.filter(l=>l.paydayId===p.id).map(l=>({childId:l.childId,gross:l.grossCents+l.matchCents,amounts:{spend:l.spendCents,save:l.saveCents+l.matchCents,give:l.giveCents}}))})),audit:[]};
}
