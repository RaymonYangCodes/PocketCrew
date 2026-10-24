import assert from 'node:assert/strict';
import fs from 'node:fs';
import vm from 'node:vm';

const source=fs.readFileSync('download-site/public/app/app.js','utf8');
const viewAs=source.slice(source.indexOf('function viewAs(event){'),source.indexOf('function updateViewAs(){'));
const context={state:{cloud:true,children:[{id:'kid',name:'Child'}]},actor:'parent',page:'Settings',cloudGeneration:0,
  childAccess:null,$:()=>({open:false}),parent:()=>context.actor==='parent',esc:s=>s,switchProfile:()=>context.prompted=true,
  close:()=>{},render:()=>{},window:{scrollTo:()=>{}}};
vm.createContext(context);vm.runInContext(viewAs,context);
context.viewAs({currentTarget:{value:'kid'}});
assert.equal(context.actor,'kid');assert.equal(context.page,'Home');assert.equal(context.cloudGeneration,1);
context.viewAs({currentTarget:{value:'parent'}});assert.equal(context.prompted,true,'Child views must use the passcode-protected profile switch');
context.actor='kid';context.viewAs({currentTarget:{value:'missing'}});assert.equal(context.actor,'kid','Invalid profile cannot change the actor');
assert.match(source,/updateViewAs\(\);/);
// Reopening starts with no family or actor, before the saved account is restored.
const nodes=new Map();
const createNode=()=>({setAttribute(){}});
const startup={state:null,actor:null,childAccess:null,esc:s=>s,viewAs(){},closeViewAsMenu(){},toggleViewAsMenu(){},parent:()=>startup.actor==='parent',
  child:()=>startup.state.children.find(c=>c.id===startup.actor),
  $:selector=>selector==='#dialog .dialog-head'?{append:n=>nodes.set('#'+n.id,n)}:nodes.get(selector),
  document:{createElement:createNode,body:{append:n=>nodes.set('#'+n.id,n)}}};
vm.createContext(startup);
vm.runInContext(source.slice(source.indexOf('function updateViewAs(){'),source.indexOf('function closeViewAsMenu(')),startup);
for(const [state,actor,label,hidden] of [
  [null,null,'Profile',true],
  [{children:[{id:'kid',name:'Child'}]},null,'Profile',true],
  [{children:[{id:'kid',name:'Child'}]},'parent','Parent',false],
  [{children:[{id:'kid',name:'Child'}]},'kid','Child',false],
  [null,null,'Profile',true]
]){
  startup.state=state;startup.actor=actor;
  assert.doesNotThrow(()=>startup.updateViewAs());
  assert.equal(nodes.get('#view-as').hidden,hidden);
  assert.equal(nodes.get('#dialog-view-as').hidden,hidden);
  assert.equal(nodes.get('#view-as').textContent,`View as · ${label} ▾`);
}
assert.match(source,/role="menuitemradio"/);
assert.match(source,/e.key==='Escape'/);
const css=fs.readFileSync('download-site/public/app/mac-theme.css','utf8');
assert.match(css,/#view-as\{position:fixed;top:calc\(12px \+ env\(safe-area-inset-top\)\);right:/);
assert.match(fs.readFileSync('download-site/public/app/cloud-actions.mjs','utf8'),/ctx.actor\(\)!=='parent'&&!ctx.access\(\)/);
console.log('View as: fixed corner, parent preview, child passcode boundary, and stale menu checks passed.');
