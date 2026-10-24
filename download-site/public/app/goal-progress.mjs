import {balance} from './domain.mjs';
export function goalProgress(state,goal){
 const amount=Math.max(0,goal.status==='completed'?goal.target:goal.featured?balance(state,goal.childId,'spend'):goal.saved);
  return {amount,percent:Math.floor(Math.min(1,amount/Math.max(1,goal.target))*100),remaining:Math.max(0,goal.target-amount)};
}
