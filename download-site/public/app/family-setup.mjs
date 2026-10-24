// The same snapshot format consumed by the native Mac app. No passcodes belong here.
export function newCloudFamily({user,name,parentName,childName,currency='USD',timezone='UTC',locale='en-US'},now=new Date()){
  if(!user?.id)throw Error('Sign in before creating a family.');
  name=name?.trim();parentName=parentName?.trim();childName=childName?.trim();
  if(!name||name.length>80||!parentName||parentName.length>80||!childName||childName.length>40)throw Error('Enter a family name, your name, and a child’s nickname.');
  if(!['USD','GBP','EUR','CAD','AUD','NZD'].includes(currency))throw Error('Choose a supported currency.');
  new Intl.DateTimeFormat(locale,{timeZone:timezone}).format(now);
  const stamp=now.toISOString(),id=()=>crypto.randomUUID(),familyId=id(),childId=id();
  const base=()=>({id:id(),createdAt:stamp,updatedAt:stamp,createdBy:user.id});
  const next=new Date(now);next.setDate(next.getDate()+7);
  return {version:1,
    family:{...base(),id:familyId,name,timezone,currency,locale,status:'active'},
    users:[{...base(),id:user.id,displayName:parentName,email:user.email,status:'active'}],
    members:[{...base(),familyId,userId:user.id,role:'guardian',inviteState:'active'},{...base(),familyId,childId,role:'child',inviteState:'active'}],
    children:[{...base(),id:childId,familyId,name:childName,ageRange:'Not specified',avatarSymbol:'star.fill',avatarHex:'#86BBD8',status:'active'}],
    schedule:{...base(),familyId,frequency:'weekly',nextPaydayAt:next.toISOString()},
    jars:['spend','save','give'].map(kind=>({...base(),familyId,childId,kind,status:'active'})),
    splits:[{...base(),childId,spendPercent:50,savePercent:40,givePercent:10}],
    matchRules:[{...base(),childId,enabled:false,percent:10}],
    workItems:[],assignments:[],submissions:[],decisions:[],earnings:[],paydays:[],paydayLines:[],ledger:[],goals:[],notifications:[],shoppingEntries:[],
    audit:[{...base(),familyId,actorId:user.id,action:'family.created',entityType:'Family',entityId:familyId,detail:'Created on the phone web app'}]};
}
