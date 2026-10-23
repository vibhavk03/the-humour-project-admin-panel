'use client';
import { useState } from 'react';
import { useRouter } from 'next/navigation';
export function SuperadminToggle({ id, name, enabled, isSelf }: { id:string; name:string; enabled:boolean; isSelf:boolean }) {
  const router = useRouter();
  const [confirming,setConfirming] = useState(false);
  const [pending,setPending] = useState(false);
  const [message,setMessage] = useState('');
  async function save() {
    setPending(true); setMessage('');
    try {
      const response = await fetch(`/api/admin/users/${id}/superadmin`, {method:'PUT',headers:{'Content-Type':'application/json'},body:JSON.stringify({enabled:!enabled,expectedStatus:enabled})});
      const result = await response.json();
      if (!response.ok) throw new Error(result.error || 'Could not update access.');
      setConfirming(false);
      if (isSelf && !result.isSuperadmin) { router.replace('/access-denied'); router.refresh(); return; }
      setMessage(result.isSuperadmin?'Superadmin access granted.':'Superadmin access removed.');
      router.refresh();
    } catch (error) { setMessage(error instanceof Error?error.message:'Could not update access. Please try again.'); }
    finally { setPending(false); }
  }
  return <div className="superadmin-control">
    <div className="superadmin-switch-row"><span>Superadmin access</span><button type="button" className="superadmin-switch" role="switch" aria-checked={enabled} aria-label={`Superadmin access for ${name}`} disabled={pending||confirming} onClick={()=>{setMessage('');setConfirming(true);}}><span /></button></div>
    {confirming && <div className="role-confirm" role="group" aria-label="Confirm access change"><p>{enabled ? `Remove control room access from ${name}?` : `Give ${name} full control room access, including permission to manage other admins?`}</p><code>{id}</code>{isSelf&&enabled&&<p>You will lose access immediately. Another superadmin must remain.</p>}<div><button type="button" disabled={pending} onClick={save}>{pending?'Saving…':enabled?'Remove access':'Grant access'}</button><button type="button" disabled={pending} onClick={()=>{setConfirming(false);setMessage('');}}>Cancel</button></div></div>}
    {message&&<p className="role-message" role="status">{message}</p>}
  </div>;
}
