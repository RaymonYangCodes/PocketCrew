import {searchShopping,sendCloudCommand} from './cloud.mjs';
import {uid,cents} from './domain.mjs';
import {photoURL,storeURL,applyLocalShopping} from './shopping-domain.mjs';

export function productArt(p,esc){const url=photoURL(p?.imageURL);return url?`<img class="product-photo" src="${esc(url)}" alt="${esc(p.title)}" loading="lazy" referrerpolicy="no-referrer">`:'<span class="product-placeholder" aria-label="Product image unavailable">◇</span>';}

export function installShopping(ctx){
  const $=s=>document.querySelector(s),esc=ctx.esc,money=ctx.money;
  let section='Shop',products=[],query='',searchError='',searching=false,searchRun=0,owner='',epoch=0;
  const parent=()=>ctx.actor()==='parent';
  const owned=()=>ctx.state().shoppingEntries?.filter(e=>parent()||e.childId===ctx.actor())||[];
  const field=(id,label,value='',type='text',extra='')=>`<label for="${id}">${label}</label><input id="${id}" type="${type}" value="${esc(value)}" ${extra}>`;
  function open(){
    if(!ctx.actor())return;
    epoch++;searchRun++;searching=false;products=[];query='';searchError='';section='Shop';owner=parent()?ctx.state().children[0]?.id:ctx.actor();draw();
  }
  function draw(){
    if(!ctx.actor())return;
    const s=ctx.state();
    ctx.modal('PocketCrew Shop',`<p>Wish for it, save for it, and let your grown-up decide.</p><div class="shop-tabs" role="tablist" aria-label="Shopping section">${['Shop','Wishlist','Cart','Purchases'].map(t=>`<button role="tab" aria-selected="${section===t}" data-shop-tab="${t}" class="${section===t?'':'quiet'}">${t}</button>`).join('')}</div><div id="shop-body"></div><p class="subtle">PocketCrew records family decisions and simulated balances. It does not order products or pay stores.</p>`);
    $('#dialog').classList.add('shopping-dialog');
    document.querySelectorAll('[data-shop-tab]').forEach(b=>b.onclick=()=>{section=b.dataset.shopTab;draw();});
    if(section==='Shop'){
      $('#shop-body').innerHTML=`${parent()&&s.children.length>1?`<label for="shop-child">Shopping for</label><select id="shop-child">${s.children.map(c=>`<option value="${c.id}" ${c.id===owner?'selected':''}>${esc(c.name)}</option>`).join('')}</select>`:''}<form id="shop-search" class="shop-search">${field('shop-query','Find an item',query,'search','maxlength="120" minlength="2" required placeholder="Headphones, books, art supplies…"')}<button type="submit" ${searching?'disabled':''}>${searching?'Searching…':'Search'}</button></form><p class="subtle">Store prices are snapshots; shipping and tax may be extra. No Mac connection needed.</p><p id="shop-error" class="error" role="alert">${esc(searchError)}</p><div id="shop-results" class="shop-grid" aria-live="polite"></div>`;
      if($('#shop-child'))$('#shop-child').onchange=e=>{owner=e.target.value;};
      const list=products;
      $('#shop-results').innerHTML=searching?'<p role="status">Finding real photos and prices…</p>':list.map((p,i)=>`<article class="card product-card">${productArt(p,esc)}${p.source==='pocketCrew'?'<span class="tag">Demo idea</span>':''}<h3>${esc(p.title)}</h3><p>Sold by ${esc(p.merchant||'Store listing')}</p><strong>${money(p.priceCents)}</strong><div class="actions"><button data-product="${i}" data-product-action="cart">${parent()?'Add to cart':'Ask to buy'}</button><button class="quiet" data-product="${i}" data-product-action="wish" data-i18n="Wishlist">Wishlist</button><button class="quiet" data-product="${i}" data-product-action="goal" data-i18n="Make a savings goal">Make a savings goal</button></div></article>`).join('')||`<p class="empty">${query?'No results. Try a different search.':'Search for something you’d like to save for.'}</p>`;
      document.querySelectorAll('[data-product]').forEach(b=>b.onclick=()=>{const product=list[Number(b.dataset.product)],childId=parent()?owner:ctx.actor();if(b.dataset.productAction==='goal')goalForm(product,childId);else commandForm('Add '+product.title,`<p>${money(product.priceCents)} · ${esc(product.merchant)}</p>`,'Add to '+(b.dataset.productAction==='wish'?'wishlist':'cart'),'add',()=>({product,childId,destination:b.dataset.productAction==='wish'?'wishlist':'awaitingApproval'}));});
      $('#shop-search').onsubmit=async e=>{
        e.preventDefault();query=$('#shop-query').value.trim();if(query.length<2)return;
        const run=++searchRun,generation=ctx.generation(),family=s.id,currentEpoch=epoch;searching=true;searchError='';products=[];draw();
        try{const result=await searchShopping(query,s.currency,ctx.access(),!s.cloud);if(run!==searchRun||generation!==ctx.generation()||ctx.state()?.id!==family||currentEpoch!==epoch||!ctx.actor())return;products=result;}
        catch(err){if(run===searchRun)searchError=err.message;}
        finally{if(run===searchRun&&generation===ctx.generation()&&currentEpoch===epoch&&ctx.actor()){searching=false;if($('#shop-body')&&$('#dialog').open)draw();}}
      };
    }else{
      const statuses={Wishlist:['wishlist'],Cart:['awaitingApproval'],Purchases:['purchased','gifted','declined']}[section];
      const entries=owned().filter(e=>statuses.includes(e.status));
      $('#shop-body').innerHTML=`${section==='Cart'?`<p class="banner">${parent()?'Approval deducts the displayed price from Spend. Giving free deducts nothing. You handle store checkout separately.':'Your parent reviews requests before anything is deducted.'}</p>`:''}${entries.map(e=>`<article class="card product-card">${productArt(e.product,esc)}<h3>${esc(e.product.title)}</h3><p>${money(e.product.priceCents)}${parent()?' · '+esc(s.children.find(c=>c.id===e.childId)?.name):''}</p><p>Sold by ${esc(e.product.merchant||'Store listing')}</p><span class="tag">${esc(({wishlist:'Wishlist',awaitingApproval:'Waiting for parent',purchased:'Purchase recorded',gifted:'Parent gift',declined:'Not this time'})[e.status])}</span>${e.parentNote?`<p>${esc(e.parentNote)}</p>`:''}${parent()&&storeURL(e.product.productURL)?`<p><a href="${esc(storeURL(e.product.productURL))}" target="_blank" rel="noopener noreferrer">Check current store details ↗</a></p>`:''}<div class="actions">${section!=='Purchases'?`${e.status==='wishlist'?button('cart','Ask to buy',e.id):''}${parent()?`${e.status==='awaitingApproval'?button('approve','Approve',e.id):''}${button('gift','Give free',e.id)}${button('price','Edit price',e.id)}${button('decline','Not now',e.id)}`:''}${button('goal','Make a savings goal',e.id)}${button('remove','Remove request',e.id)}`:''}</div></article>`).join('')||'<p class="empty">Nothing here yet. Find an item in Shop to get started.</p>'}`;
      document.querySelectorAll('[data-shop-action]').forEach(b=>b.onclick=()=>entryAction(b.dataset.shopAction,owned().find(e=>e.id===b.dataset.id)));
    }
  }
  function button(action,title,id){return `<button class="quiet" data-shop-action="${action}" data-id="${id}">${title}</button>`;}
  function commandForm(title,html,label,action,data,sensitive=false){
    if(ctx.state()?.cloud&&!parent()&&!ctx.access()){ctx.toast('This is a child view preview. Return to Parent to make changes.');return;}
    if(sensitive&&!ctx.hasPin()){ctx.setupPin();return;}
    epoch++;const currentEpoch=epoch,snapshot=ctx.state(),generation=ctx.generation(),actor=ctx.actor(),access=ctx.access(),key=uid();
    ctx.modal(title,`<form id="shopping-command">${html}${sensitive?field('shopping-pin','Parent passcode','', 'password','inputmode="numeric" required'):''}<p class="error" id="shopping-error" role="alert"></p><button type="submit">${label}</button><button type="button" class="quiet" id="shopping-back">Back to shop</button></form>`);
    $('#shopping-back').onclick=()=>{epoch++;draw();};
    let busy=false;
    $('#shopping-command').onsubmit=async e=>{
      e.preventDefault();if(busy)return;busy=true;const form=e.currentTarget,submit=e.submitter;submit.disabled=true;
      try{
        if(sensitive)await ctx.checkPin($('#shopping-pin').value);
        if(generation!==ctx.generation()||ctx.actor()!==actor)throw Error('Unlock your profile again.');
        const payload=data();
        if(snapshot.cloud){const next=await sendCloudCommand(snapshot,action,payload,key,access,'family_shopping_command');if(generation!==ctx.generation()||ctx.actor()!==actor)return;ctx.accept(next);}
        else await ctx.local(s=>applyLocalShopping(s,actor,action,payload));
        if(currentEpoch!==epoch||generation!==ctx.generation()||ctx.actor()!==actor)return;
        ctx.toast(action==='goal'&&!parent()?'Goal idea sent to your parent.':'Saved.');draw();
      }catch(err){if(form.isConnected&&generation===ctx.generation())$('#shopping-error').textContent=err.message;}
      finally{busy=false;submit.disabled=false;}
    };
  }
  document.addEventListener('click',e=>{
    const complete=e.target.closest('[data-act="complete-goal"]');
    if(complete&&parent()){
      e.stopImmediatePropagation();
      const goal=ctx.state().goals.find(g=>g.id===complete.dataset.id);
      if(!goal)return;
      commandForm('Complete this goal?',`<h3>${esc(goal.title)}</h3><p>Deduct ${money(goal.target)} from Spend and mark this goal completed. This does not place a store order.</p>`,'Confirm completion','completeGoal',()=>({id:goal.id,expectedPrice:goal.target}),true);return;
    }
    const remove=e.target.closest('[data-act="remove-goal"]');
    if(remove&&ctx.actor()){
      e.stopImmediatePropagation();
      const goal=ctx.state().goals.find(g=>g.id===remove.dataset.id);
      if(!goal||(!parent()&&goal.childId!==ctx.actor()))return;
      commandForm('Remove this savings goal?',`<h3>${esc(goal.title)}</h3><p>This archives the goal. Your savings and transaction history stay unchanged. You can choose another featured goal afterward.</p>`,'Remove goal','archiveGoal',()=>({id:goal.id}));return;
    }
    const b=e.target.closest('[data-act="feature-goal"]');
    if(!b||!ctx.actor())return;
    e.stopImmediatePropagation();
    const goal=ctx.state().goals.find(g=>g.id===b.dataset.id);
    if(!goal||(!parent()&&goal.childId!==ctx.actor()))return;
    commandForm('Feature this goal?',`<h3>${esc(goal.title)}</h3><p>This becomes your featured goal. Future Save deposits go toward it; existing money stays where it is.</p>`,'Make featured','featureGoal',()=>({id:goal.id}));
  },true);
  function goalForm(product,childId,id){
    commandForm(parent()?'Create a savings goal':'Propose a savings goal',`${productArt(product,esc)}<p>Sold by ${esc(product.merchant||'Seller not provided')} · ${money(product.priceCents)}</p><p>${parent()?'New Save deposits go to the featured goal.':'Your parent will review this idea before it becomes active.'}</p>${field('shopping-title','Goal title',product.title,'text','maxlength="240" required')}${field('shopping-target','Target amount',(product.priceCents/100).toFixed(2),'number','step="0.01" min="0.01" required')}${field('shopping-date','Target date (optional)','','date')}`,parent()?'Create goal':'Send idea','goal',()=>({id,product,childId,title:$('#shopping-title').value,target:cents($('#shopping-target').value),targetDate:$('#shopping-date').value}));
  }
  function entryAction(action,e){
    if(!e)return;
    if(action==='goal'){goalForm(e.product,e.childId,e.id);return;}
    if(action==='price'){commandForm('Edit item price',`<h3>${esc(e.product.title)}</h3><p>This changes the amount charged to Spend on approval, not the store price or an existing goal.</p>${field('shopping-price','New price',(e.product.priceCents/100).toFixed(2),'number','step="0.01" min="0.01" required')}${field('shopping-reason','Reason — sale or parent contribution','','text','maxlength="1000" required')}`,'Save price',action,()=>({id:e.id,priceCents:cents($('#shopping-price').value),reason:$('#shopping-reason').value}),true);return;}
    commandForm(({approve:'Approve purchase?',gift:'Give as a gift?',decline:'Not this time',remove:'Remove this request?',cart:'Ask to buy?'})[action],`<h3>${esc(e.product.title)}</h3><p>${action==='approve'?money(e.product.priceCents)+' will be deducted from Spend. This does not place a store order.':action==='gift'?'A parent gift — no money will be deducted.':'No money will be deducted.'}</p>${action==='decline'?field('shopping-reason','Kind reason','','text','required maxlength="1000"'):''}`,'Confirm',action,()=>({id:e.id,expectedPrice:e.product.priceCents,reason:$('#shopping-reason')?.value}),['approve','gift'].includes(action));
  }
  document.addEventListener('click',e=>{const b=e.target.closest('button');if(b?.dataset.act==='shop'){e.stopImmediatePropagation();open();}if(b?.dataset.act==='review-shopping-goal'&&parent()){const g=ctx.state().goals.find(g=>g.id===b.dataset.id);commandForm('Review savings goal',`${g.shoppingProduct?productArt(g.shoppingProduct,esc):''}<h3>${esc(g.title)}</h3><p>${money(g.target)}</p><label for="goal-decision">Decision</label><select id="goal-decision"><option value="active">Approve goal</option><option value="archived">Not now</option></select>`,'Save decision','reviewGoal',()=>({id:g.id,decision:$('#goal-decision').value}));}},true);
}
