import {allocation,uid} from './domain.mjs';
export function addMoney(state,actor,childId,amount,reason='Parent deposit') {
  if(actor!=='parent')throw Error('A parent needs to do this.');
  const child=state.children.find(c=>c.id===childId);
  if(!child||!Number.isSafeInteger(amount)||amount<=0||amount>100000000)throw Error('Choose a child and a positive amount up to 1,000,000.');
  const split=allocation(amount,child.split),at=new Date().toISOString(),depositId=uid();
  const entries=Object.entries(split).filter(([,value])=>value>0).map(([jar,value])=>({id:uid(),childId,jar,amount:value,category:'adjustment',description:'Money added · '+(reason.trim()||'Parent deposit'),at,depositId}));
  state.ledger.push(...entries);
  state.audit.push({id:depositId,at,actor,action:'Added money',entityId:childId});
}
