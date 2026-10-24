// Cloud data stays in memory, separate from the existing device-local family.
export function cloudBanner(esc,email,isChild=false){return `<section class="banner"><strong>${isChild?'Your private child connection':'Connected to your Mac family'}</strong><p>${isChild?'Only your profile is available here.':'Parent view · '+esc(email)+'.'} Updates are checked every second while this app is open and your profile is unlocked. Work, shopping lists, purchases and savings goals sync with your Mac family. Use the Mac app for adding children, recurring schedules and proof photos.</p><div class="actions"><button class="quiet" data-act="cloud-reload">Refresh family</button>${isChild?'':'<button class="quiet" data-act="cloud-pin">Parent profile passcode</button><button class="quiet" data-act="child-invite">Connect a child’s device</button><button class="quiet" data-act="cloud-join">Join with a parent invitation</button>'}<button class="danger" data-act="cloud-signout" data-i18n="Sign Out">Sign Out</button></div><p id="cloud-status" role="status"></p></section>`;}
export function finishCloudView(state,isChild=false){
  if(!state?.cloud)return;
  // Locking a profile does not revoke the remembered account.
  // Expose only server-validated commands for the active role.
  const allowed=new Set(isChild?['cloud-reload','cloud-signout','start','submit']:['cloud-reload','cloud-signout','cloud-join','child-invite','export','create-work','presets','review','edit-child','remove-child','goal','purchase','payday','schedule','cloud-pin']);
  allowed.add('switch');allowed.add('lock');allowed.add('walkthrough');
  allowed.add('check-updates');
  // Shopping mutations are authenticated and checked by family_shopping_command.
  allowed.add('shop');allowed.add('feature-goal');allowed.add('remove-goal');
  if(!isChild){allowed.add('review-shopping-goal');allowed.add('complete-goal');}
  document.querySelectorAll('main button[data-act]').forEach(button=>{if(!allowed.has(button.dataset.act))button.remove();});
  document.querySelectorAll('.save-status').forEach(el=>el.textContent='Cloud family · Synced '+(isChild?'child':'parent')+' connection');
  document.querySelectorAll('main .subtle,main .footer-note').forEach(el=>{
    if(/No Mac sync|Passcodes help/.test(el.textContent))el.remove();
  });
  const h=document.querySelector('main h1');
  if(h?.textContent==='Family settings')h.textContent='Family profiles';
}
