'use client';
import { useState } from 'react';
import { useRouter } from 'next/navigation';
import type { MediaDetail } from '@/lib/media/types';
export function MediaEditor({post}:{post:MediaDetail}) {
  const router=useRouter(); const [current,setCurrent]=useState(post);
  const [caption,setCaption]=useState(post.caption??''); const [context,setContext]=useState(post.context??'');
  const [busy,setBusy]=useState(false); const [confirming,setConfirming]=useState(false); const [confirmation,setConfirmation]=useState('');
  const [message,setMessage]=useState(''); const [failed,setFailed]=useState(false); const [deleted,setDeleted]=useState(false);
  const dirty=caption!==(current.caption??'')||context!==(current.context??'');
  async function submit(remove:boolean){
    setBusy(true);setMessage('');setFailed(false);
    try{
      const response=await fetch(`/api/admin/media/${post.id}`,{method:remove?'DELETE':'PATCH',headers:{'Content-Type':'application/json'},body:JSON.stringify({expectedVersion:current.version,caption,context})});
      const result=await response.json(); if(!response.ok)throw new Error(result.error||'The change could not be saved.');
      if(remove){setDeleted(true);setConfirming(false);if(result.cleanupPending){setMessage('Post and votes deleted. Image cleanup is pending; retry below.');}else{router.replace('/media?deleted=1');router.refresh();}return;}
      setCurrent(result.post);setCaption(result.post.caption??'');setContext(result.post.context??'');setMessage('Changes saved.');router.refresh();
    }catch(error){setFailed(true);setMessage(error instanceof Error?error.message:'Could not save. Please try again.');}
    finally{setBusy(false);}
  }
  return <section className="media-editor"><span className="eyebrow">EDIT POST</span><h2>The final word.</h2><p className="editor-intro">Caption changes appear in the main app. The original author and AI generation details stay attached.</p>
    {!deleted&&<form onSubmit={event=>{event.preventDefault();submit(false);}}><label htmlFor="media-caption">Caption <span>{caption.length}/200</span></label><textarea id="media-caption" value={caption} maxLength={200} rows={4} onChange={event=>setCaption(event.target.value)} disabled={busy} required={current.caption!==null}/>{current.caption===null&&<p className="field-note">This upload is unpublished. Saving a caption will publish it to the public feed.</p>}
      <label htmlFor="media-context">Private context <span>{context.length}/1000</span></label><textarea id="media-context" value={context} maxLength={1000} rows={4} onChange={event=>setContext(event.target.value)} disabled={busy}/><p className="field-note">Context stays private. Editing it does not regenerate the caption.</p>
      <div className="editor-actions"><button className="primary-button" disabled={busy||!dirty||confirming}>{busy?'Saving…':'Save changes'}</button><button type="button" className="refresh-link" disabled={busy||!dirty} onClick={()=>{setCaption(current.caption??'');setContext(current.context??'');setMessage('');}}>Reset edits</button></div>
    </form>}
    {message&&<p className={`media-message${failed?' error':''}`} role="status">{message}{failed&&message.includes('Reload')&&<button type="button" className="refresh-link" onClick={()=>window.location.reload()}>Reload post</button>}</p>}
    <div className="media-danger"><h3>{deleted?'Image cleanup':'Delete post'}</h3><p>{deleted?'The post is no longer visible. Retry to remove the remaining stored image.':'Permanently removes this post, all its votes, and its stored image. This cannot be undone.'}</p>
      {deleted?<button className="delete-button" disabled={busy} onClick={()=>submit(true)}>{busy?'Cleaning up…':'Retry image cleanup'}</button>:confirming?<div className="delete-confirm"><p>Delete the saved post by <strong>{post.author_name||'Unnamed contributor'}</strong>?</p><code>{post.id}</code><label htmlFor="confirm-delete">Type DELETE to confirm</label><input id="confirm-delete" value={confirmation} onChange={event=>setConfirmation(event.target.value)} autoComplete="off" disabled={busy}/><div><button className="delete-button" disabled={busy||confirmation!=='DELETE'} onClick={()=>submit(true)}>{busy?'Deleting…':'Permanently delete post'}</button><button className="refresh-link" disabled={busy} onClick={()=>{setConfirming(false);setConfirmation('');}}>Cancel</button></div></div>:<button className="delete-button" disabled={busy} onClick={()=>{setConfirming(true);setConfirmation('');setMessage('');}}>Delete post…</button>}
    </div>
  </section>;
}
