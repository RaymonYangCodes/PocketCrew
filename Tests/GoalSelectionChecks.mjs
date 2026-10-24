import assert from 'node:assert/strict';
import {applyLocalShopping} from '../download-site/public/app/shopping-domain.mjs';
const s={children:[{id:'a'},{id:'b'}],ledger:[{amount:100}],goals:[
  {id:'one',childId:'a',status:'active',featured:true,saved:10,target:100},
  {id:'two',childId:'a',status:'active',featured:false,saved:0,target:100},
  {id:'sibling',childId:'b',status:'active',featured:true,saved:0,target:100},
  {id:'pending',childId:'a',status:'proposed',featured:false,saved:0,target:100}
]};
const ledger=JSON.stringify(s.ledger);
applyLocalShopping(s,'a','featureGoal',{id:'two'});
assert.equal(s.goals[0].featured,false);assert.equal(s.goals[1].featured,true);
assert.equal(s.goals[2].featured,true);assert.equal(JSON.stringify(s.ledger),ledger);
assert.throws(()=>applyLocalShopping(s,'a','featureGoal',{id:'sibling'}));
assert.throws(()=>applyLocalShopping(s,'a','featureGoal',{id:'pending'}));
assert.throws(()=>applyLocalShopping(s,null,'featureGoal',{id:'two'}));
console.log('Featured goal ownership, approval and unchanged balances passed.');
assert.throws(()=>applyLocalShopping(s,'a','archiveGoal',{id:'sibling'}));
assert.throws(()=>applyLocalShopping(s,null,'archiveGoal',{id:'one'}));
applyLocalShopping(s,'a','archiveGoal',{id:'one'});
assert.equal(s.goals[0].status,'archived');
assert.equal(s.goals[0].saved,10);
assert.equal(s.goals[0].featured,false);
assert.throws(()=>applyLocalShopping(s,'a','archiveGoal',{id:'one'}));
applyLocalShopping(s,'parent','archiveGoal',{id:'sibling'});
assert.equal(s.goals[2].status,'archived');
assert.equal(JSON.stringify(s.ledger),ledger);
console.log('Child and parent goal removal preserves savings and enforces ownership.');
