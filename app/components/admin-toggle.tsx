'use client';
import { useState } from 'react';
import { useRouter } from 'next/navigation';
export function AdminToggle({ id, name, enabled }: { id:string; name:string; enabled:boolean }) {
  const router = useRouter();
  const [confirming,setConfirming] = useState(false);
  const [pending,setPending] = useState(false);
  const [message,setMessage] = useState('');
  async function save() {
    setPending(true); setMessage('');
    try {
      const response = await fetch(`/api/admin/users/${id}/admin`, {method:'PUT',headers:{'Content-Type':'application/json'},body:JSON.stringify({enabled:!enabled,expectedStatus:enabled})});
      const result = await response.json();
      if (!response.ok) throw new Error(result.error || 'Could not update access.');
      setConfirming(false);
      setMessage(result.isAdmin?'Admin access granted.':'Admin access removed.');
      router.refresh();
    } catch (error) { setMessage(error instanceof Error?error.message:'Could not update access. Please try again.'); }
    finally { setPending(false); }
  }
  return <div className="superadmin-control">
    <div className="superadmin-switch-row"><span>Admin access</span><button type="button" className="superadmin-switch" role="switch" aria-checked={enabled} aria-label={`Admin access for ${name}`} disabled={pending||confirming} onClick={()=>{setMessage('');setConfirming(true);}}><span /></button></div>
    {confirming && <div className="role-confirm" role="group" aria-label="Confirm access change"><p>{enabled ? `Remove control room access from ${name}?` : `Give ${name} control room access to view users and ratings and manage ordinary users’ media?`}</p><code>{id}</code><div><button type="button" disabled={pending} onClick={save}>{pending?'Saving…':enabled?'Remove access':'Grant access'}</button><button type="button" disabled={pending} onClick={()=>{setConfirming(false);setMessage('');}}>Cancel</button></div></div>}
    {message&&<p className="role-message" role="status">{message}</p>}
  </div>;
}
