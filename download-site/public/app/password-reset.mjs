const BASE='https://bvfzqfeyxyjycmkpifgz.supabase.co/auth/v1';
const KEY='sb_publishable_rSy5ZLM5o5IQnmvyJoMyhw_Ecl_Zq_t';
let recoveryToken=null;
export async function sendPasswordReset(email){
  const response=await fetch(BASE+'/recover?redirect_to='+encodeURIComponent('https://pocket-crew.vercel.app/app/'),{method:'POST',headers:{apikey:KEY,'Content-Type':'application/json'},body:JSON.stringify({email:email.trim()})});
  if(!response.ok)throw Error('Could not send the reset link. Please wait a moment and try again.');
}
export async function readPasswordRecovery(){
  const hash=new URLSearchParams(location.hash.slice(1));
  if(hash.has('error')){history.replaceState(null,'','/app/');throw Error('This sign-in or reset link has expired. Request a new link.');}
  if(hash.get('type')!=='recovery')return false;
  const token=hash.get('access_token');history.replaceState(null,'','/app/');
  if(!token)throw Error('This reset link is incomplete. Request a new link.');
  const response=await fetch(BASE+'/user',{headers:{apikey:KEY,Authorization:'Bearer '+token}});
  if(!response.ok)throw Error('This reset link has expired. Request a new link.');
  recoveryToken=token;return true;
}
export async function saveRecoveredPassword(password){
  if(!recoveryToken)throw Error('Open a new reset link from your email first.');
  if(password.length<8)throw Error('Use at least 8 characters.');
  const response=await fetch(BASE+'/user',{method:'PUT',headers:{apikey:KEY,Authorization:'Bearer '+recoveryToken,'Content-Type':'application/json'},body:JSON.stringify({password})});
  if(!response.ok)throw Error('The password could not be changed. Try a stronger password, or request a new reset link.');
  recoveryToken=null;
}
