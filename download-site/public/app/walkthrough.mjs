export function walkthroughSteps(parent){
  const common=[
  [
    "Home",
    ".profilebar",
    "Your profile",
    "Switch between people here. Profiles keep each person’s tasks and savings separate."
  ],
  [
    "Home",
    ".payday",
    "Next payday",
    "See approved earnings and the scheduled payday. No real funds are held by PocketCrew."
  ],
  [
    "Work",
    "#nav [data-page=\"Work\"]",
    "Tasks",
    "Assigned responsibilities and paid gigs live here."
  ],
  [
    "Work",
    "[data-tab=\"My work\"]",
    "My tasks",
    "Start assigned work and submit it when finished. Parents review submissions."
  ],
  [
    "Work",
    "[data-tab=\"Available gigs\"]",
    "Available gigs",
    "Claim an open paid gig before starting it."
  ],
  [
    "Work",
    "[data-tab=\"Completed\"]",
    "Completed tasks",
    "Look back at finished tasks and their decisions."
  ],
  [
    "Payday",
    "#main h1",
    "Payday",
    "Parents confirm payday after reviewing approved earnings. Children can see their upcoming split."
  ],
  [
    "Jars",
    "#main .jars",
    "Your money jars",
    "Spend is for purchases, Save for goals, and Give for generosity. Each child has a separate split."
  ],
  [
    "Jars",
    "#history-search",
    "Search history",
    "Find a transaction by its description."
  ],
  [
    "Jars",
    "#history-filter",
    "Filter history",
    "Narrow the history to payday, a jar, or adjustments."
  ],
  [
    "Jars",
    "[data-act=\"shop\"]",
    "Open the shopping center",
    "Shop, Wishlist, Cart and Purchases are all inside PocketCrew."
  ],
  [
    "Jars",
    "#shop-query",
    "Search items",
    "Type what you are looking for here. This tour does not search or spend anything.",
    "shop"
  ],
  [
    "Jars",
    "#shop-search button",
    "Search button",
    "Run your search to see the available results. Prices may change, and shipping and tax may be extra.",
    "shop"
  ],
  [
    "Jars",
    "[data-shop-tab=\"Wishlist\"]",
    "Wishlist",
    "Keep ideas here without spending money. You can later ask to buy or propose a savings goal.",
    "shop"
  ],
  [
    "Jars",
    "[data-shop-tab=\"Cart\"]",
    "Cart",
    "Requests wait for a parent here. Only a parent can approve them, edit their recorded prices or give them as gifts.",
    "shop"
  ],
  [
    "Jars",
    "[data-shop-tab=\"Purchases\"]",
    "Purchases",
    "Look back at approved purchases, gifts and declined requests. Approval records a ledger entry, not a store order.",
    "shop"
  ],
  [
    "Jars",
    "#close-dialog",
    "Close shopping",
    "Close returns to the main app. Opening or closing the shop does not change balances.",
    "shop"
  ]
];
  const details=parent?[
  [
    "Profile",
    "[data-act=\"add-child\"]",
    "Add Child",
    "Create a separate profile and passcode for another child."
  ],
  [
    "Profile",
    "#name",
    "Child nickname",
    "Choose the name shown on this child’s profile.",
    "add-child"
  ],
  [
    "Profile",
    "#new-pin",
    "Child passcode",
    "Set a private passcode for this profile. The walkthrough never fills or saves passcodes.",
    "add-child"
  ],
  [
    "Profile",
    "#spend",
    "Spend percentage",
    "Choose how much of this child’s payday goes to Spend. The three percentages must total 100%.",
    "add-child"
  ],
  [
    "Profile",
    "#save",
    "Save percentage",
    "Choose how much goes toward this child’s savings.",
    "add-child"
  ],
  [
    "Profile",
    "#give",
    "Give percentage",
    "Choose how much goes toward generosity. Each child can have different settings.",
    "add-child"
  ],
  [
    "Profile",
    "[data-act=\"edit-child\"]",
    "Edit a child",
    "Change the child’s nickname or jar split here."
  ],
  [
    "Profile",
    "[data-act=\"remove-child\"]",
    "Remove a child",
    "This asks for confirmation and checks unsettled balances and work. The tour never removes anyone."
  ],
  [
    "Work",
    "[data-act=\"presets\"]",
    "Presets",
    "Open a ready-made idea, edit it, and save only when you are ready. Done hides suggestions; this button brings them back."
  ],
  [
    "Work",
    "#type, #cloud-type",
    "Task type",
    "Choose a paid gig or an unpaid responsibility.",
    "create-work"
  ],
  [
    "Work",
    "#title, #cloud-title",
    "Task name",
    "Write a short name that makes the job clear.",
    "create-work"
  ],
  [
    "Work",
    "#instructions, #cloud-instructions",
    "Task instructions",
    "Explain what a finished task should look like.",
    "create-work"
  ],
  [
    "Work",
    "#assignee, #cloud-child",
    "Assign the task",
    "Choose a child or make a paid gig available to claim.",
    "create-work"
  ],
  [
    "Work",
    "#reward, #cloud-reward",
    "Gig reward",
    "Set the reward before the child starts. Unpaid responsibilities do not earn money.",
    "create-work"
  ],
  [
    "Work",
    "#due, #cloud-due",
    "Due date",
    "Choose when the task should be finished. Saving adds the task; this tour never presses Save.",
    "create-work"
  ],
  [
    "Settings",
    "[data-act=\"schedule\"]",
    "Payday schedule",
    "Open the schedule from Settings."
  ],
  [
    "Settings",
    "#payday-frequency, #cloud-frequency",
    "Frequency",
    "Choose a repeat schedule. Custom displays Every [number] days.",
    "schedule"
  ],
  [
    "Settings",
    "#payday-date, #cloud-date",
    "Next payday",
    "Choose the next payday date, then save to apply the schedule.",
    "schedule"
  ],
  [
    "Jars",
    "[data-act=\"feature-goal\"]",
    "Featured goals",
    "Make featured selects the goal for future Save allocations without moving money already saved."
  ],
  [
    "Jars",
    "[data-act=\"remove-goal\"]",
    "Remove a savings goal",
    "Archive a goal after confirmation. Savings and transaction history remain unchanged."
  ]
]:[
  [
    "Jars",
    "[data-act=\"feature-goal\"], #main .jars",
    "Choose your featured goal",
    "Use Make featured on one of your approved goals. Future Save deposits go toward it; existing money stays put."
  ],
  [
    "Jars",
    "[data-act=\"remove-goal\"], #main .jars",
    "Remove your own goal",
    "Remove goal archives your goal after confirmation. It does not take away your savings."
  ],
  [
    "Profile",
    "#main h1",
    "Your profile",
    "Your name and jar split belong to you. Ask your grown-up about changes to your split."
  ],
  [
    "Settings",
    "[data-act=\"lock\"]",
    "Lock your profile",
    "Lock profiles on a shared device. This does not sign out of the family account."
  ]
];
  return [
    common[0], common[1], common[2],
    ["Work","#main h1",parent?"Manage tasks":"Finish a task",parent?"Create responsibilities or paid gigs and review submitted tasks.":"Claim an available gig, start it, then submit your finished task for a parent to approve."],
    parent?["Work","[data-act=\"presets\"]","Task presets","Choose a category and an idea, then edit its details before saving."]:["Work","[data-tab=\"Available\"]","Available gigs","Choose a gig to claim it. Your parent reviews your completed work."],
    parent?["Home","[data-act=\"add-child\"], .profilebar","Your family","Add children from Family or Home. Each child has their own profile, passcode and money split."]:["Profile","#main h1","Your profile","See your personal money split and suggest a gig."],
    ["Payday","#main h1","Payday",parent?"Review approved earnings and confirm payday.":"See when approved earnings will reach your jars."],
    ["Jars","#main .jars","Jars and savings goals","Spend, Save and Give each have a job. Create a goal, make it featured, or remove it without losing your saved money."],
    ["Home","[data-act=\"shop\"]","PocketCrew Shop","Search products, save wishes, request purchases or make a savings goal. Parents approve requests; actual checkout happens at the store."],
    ["Settings","[data-act=\"walkthrough\"]","Settings and replay","Find your settings and Take a tour here. Lock profiles on shared devices; Sign Out disconnects your account."]
  ];
}
export function installWalkthrough(ctx){
  let tour=null,lastFocus=null,tourModal=false,previousGeometry=null;
  const reducedMotion=()=>window.matchMedia('(prefers-reduced-motion: reduce)').matches;
  function captureGeometry(){
    const spot=document.querySelector('#crew-spotlight'),panel=document.querySelector('#crew-tour');
    if(spot&&panel)previousGeometry=[spot,panel].map(el=>{
      const r=el.getBoundingClientRect();
      return {left:r.left+'px',top:r.top+'px',width:r.width+'px',height:r.height+'px',borderRadius:getComputedStyle(el).borderRadius};
    });
  }
  function animateGeometry(spot,panel){
    if(previousGeometry&&!reducedMotion())[spot,panel].forEach((el,i)=>{
      const r=el.getBoundingClientRect();
      el.animate([previousGeometry[i],{left:r.left+'px',top:r.top+'px',width:r.width+'px',height:r.height+'px',borderRadius:getComputedStyle(el).borderRadius}],{duration:420,easing:'cubic-bezier(.22,1,.36,1)'});
    });
    previousGeometry=null;
  }
  const key=()=>`pocketcrew.walkthrough.v1:${ctx.family()}:${ctx.actor()}`;
  const seen=()=>{try{return localStorage.getItem(key());}catch{return true;}};
  function clearStep(){document.querySelector('#crew-tour')?.remove();document.querySelector('#crew-spotlight')?.remove();document.querySelectorAll('[data-tour-inert]').forEach(el=>{el.inert=false;delete el.dataset.tourInert;});if(tourModal){tourModal=false;document.querySelector('#dialog')?.close();}}
  function finish(){if(!tour)return;try{localStorage.setItem(tour.key,'done');}catch{}tour=null;previousGeometry=null;clearStep();lastFocus?.isConnected&&lastFocus.focus();}
  function position(){
    if(!tour)return;
    const target=document.querySelector(tour.steps[tour.index][1]),spot=document.querySelector('#crew-spotlight'),panel=document.querySelector('#crew-tour');
    if(!spot||!panel)return;
    const r=target?.getBoundingClientRect();spot.style.display=r?'block':'none';
    if(r)Object.assign(spot.style,{left:Math.max(4,r.left-5)+'px',top:Math.max(4,r.top-5)+'px',width:Math.min(r.width+10,innerWidth-8)+'px',height:Math.min(r.height+10,innerHeight-8)+'px',borderRadius:(parseFloat(getComputedStyle(target).borderTopLeftRadius)||0)+5+'px'});
    const w=panel.offsetWidth,h=panel.offsetHeight,gap=18;
    let x=(innerWidth-w)/2,y=(innerHeight-h)/2;
    if(r){
      x=r.left+(r.width-w)/2;y=r.bottom+gap;
      if(r.right+gap+w<=innerWidth-16){x=r.right+gap;y=r.top+(r.height-h)/2;}
      else if(r.left-gap-w>=16){x=r.left-gap-w;y=r.top+(r.height-h)/2;}
      else if(y+h>innerHeight-16)y=r.top-gap-h;
    }
    Object.assign(panel.style,{left:Math.max(16,Math.min(innerWidth-w-16,x))+'px',top:Math.max(16,Math.min(innerHeight-h-16,y))+'px',right:'auto',bottom:'auto'});
  }
  function draw(){
    if(!tour)return;
    if(tour.key!==key()||!ctx.actor()){finish();return;}
    const [page,selector,title,body,openAction]=tour.steps[tour.index];
    captureGeometry();clearStep();
    if(ctx.page()!==page){ctx.navigate(page);queueMicrotask(draw);return;}
    if(openAction){
      const safeActions=['shop','add-child','create-work','schedule'];
      const trigger=document.querySelector(`main [data-act="${openAction}"]`);
      if(safeActions.includes(openAction)&&trigger&&!trigger.disabled){trigger.click();tourModal=!!document.querySelector('#dialog')?.open;}
    }
    // Cloud families and empty families may not expose every optional control.
    if(!document.querySelector(selector)&&tour.index<tour.steps.length-1){tour.steps.splice(tour.index,1);draw();return;}
    document.querySelector('#crew-tour')?.remove();document.querySelector('#crew-spotlight')?.remove();
    document.querySelector(selector)?.scrollIntoView({block:'center',behavior:'instant'});
    const host=tourModal?document.querySelector('#dialog'):document.body;
    const spot=document.createElement('div');spot.id='crew-spotlight';spot.setAttribute('aria-hidden','true');host.append(spot);
    const panel=document.createElement('section');panel.id='crew-tour';panel.setAttribute('role','dialog');panel.setAttribute('aria-modal','true');panel.setAttribute('aria-labelledby','crew-tour-title');
    panel.innerHTML=`<p class="eyebrow">Interactive walkthrough · ${tour.index+1} of ${tour.steps.length}</p><h2 id="crew-tour-title">${title}</h2><p>${body}</p><div class="actions"><button class="quiet" data-tour="skip">Skip tour</button><button class="quiet" data-tour="back" ${tour.index===0?'disabled':''}>Back</button><button data-tour="next">${tour.index===tour.steps.length-1?'Done!':'Next'}</button></div>`;
    host.append(panel);
    for(const el of document.querySelectorAll('main,nav,header,#dialog-body,#close-dialog')){if(!el.inert){el.inert=true;el.dataset.tourInert='true';}}
    panel.onclick=e=>{const action=e.target.closest('[data-tour]')?.dataset.tour;if(action==='skip'||action==='next'&&tour.index===tour.steps.length-1){finish();return;}if(action==='next'||action==='back'){tour.index+=action==='next'?1:-1;draw();}};
    panel.onkeydown=e=>{if(e.key==='Escape'){e.preventDefault();finish();}if(e.key==='Tab'){const buttons=[...panel.querySelectorAll('button:not(:disabled)')],first=buttons[0],last=buttons.at(-1);if(e.shiftKey&&document.activeElement===first){e.preventDefault();last.focus();}else if(!e.shiftKey&&document.activeElement===last){e.preventDefault();first.focus();}}};
    panel.querySelector('[data-tour="next"]').focus({preventScroll:true});position();animateGeometry(spot,panel);
  }
  function start(){if(!ctx.actor()||document.querySelector('#dialog')?.open)return;lastFocus=document.activeElement;tour={key:key(),index:0,steps:walkthroughSteps(ctx.actor()==='parent')};draw();}
  document.addEventListener('click',e=>{if(e.target.closest('[data-act="walkthrough"]'))start();});
  window.addEventListener('resize',position);window.addEventListener('scroll',position,true);
  return {refresh(){if(tour){if(tour.key!==key()||!ctx.actor())finish();else position();return;}if(ctx.actor()&&!seen()&&!document.querySelector('#dialog')?.open)start();}};
}
