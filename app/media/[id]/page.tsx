import Link from 'next/link';
import { notFound } from 'next/navigation';
import { requireAdmin } from '@/lib/auth/server';
import { AdminShell } from '@/app/components/admin-shell';
import { ProfilePostImage } from '@/app/components/profile-post-image';
import { RemixComposer } from '@/app/components/remix-composer';
import { MediaEditor } from '@/app/components/media-editor';
import { validUserId,displayDate } from '@/lib/users/types';
import type { MediaDetail } from '@/lib/media/types';
export default async function MediaPost({params}:{params:Promise<{id:string}>}){
  const {client,user}=await requireAdmin(); const {id}=await params; if(!validUserId(id))notFound();
  const {data,error}=await client.rpc('admin_media_detail',{target_id:id}); if(!error&&!data)notFound(); const post=!error&&data?data as MediaDetail:null;
  const {data:adminProfile}=await client.from('profiles').select('first_name,last_name').eq('id',user.id).maybeSingle();
  const adminName=[adminProfile?.first_name,adminProfile?.last_name].filter(Boolean).join(' ').trim() || 'my admin account';
  const {data:lineage}=post?await client.rpc('admin_remix_provenance',{target_id:id}):{data:null};
  return <AdminShell email={user.email} active="media"><main className="pulse-main"><Link href="/media" className="back-link">← Back to media</Link>{!post?<section className="pulse-error" role="alert"><h2>This post is temporarily unavailable.</h2><p>Try refreshing in a moment.</p></section>:<><div className="pulse-heading"><div><span className="eyebrow">POST DETAIL</span><h1>The punchline<span>.</span></h1><p>Review, refine, or remove this post.</p></div><span className="role-badge">{post.caption!==null?'Published':'Unpublished'}</span></div>
    <div className="media-detail-grid"><div><section className="media-preview"><ProfilePostImage userId={post.user_id} postId={post.id}/><div>{lineage&&<p className="remix-lineage">Remixed from {lineage.source_author_name||'a community contributor'}{lineage.source_exists&&<> · <Link href={`/media/${lineage.source_post_id}`}>View source post ↗</Link></>}</p>}<p className="preview-caption">{post.caption??'No caption saved.'}</p><Link href={`/users/${post.user_id}`}>{post.author_name||'Unnamed contributor'}</Link><p>{displayDate(post.created_at)}</p><div className="post-ratings"><span>↑ {post.upvotes} upvotes</span><span>↓ {post.downvotes} downvotes</span><strong>Net {post.upvotes-post.downvotes}</strong></div><Link className="media-manage" href={`/ratings?post=${post.id}`}>View individual ratings ↗</Link><code className="post-id">{post.id}</code></div></section>
    <details className="generation-details"><summary>Original AI generation details</summary><dl><dt>Model</dt><dd>{post.model||'Not recorded'}</dd><dt>Prompt version</dt><dd>{post.prompt_version||'Not recorded'}</dd><dt>Generation prompt</dt><dd><pre>{post.generation_prompt||'Not recorded'}</pre></dd><dt>Original author ID</dt><dd><code>{post.user_id}</code></dd></dl><p>These describe the original generation. Admin caption/context edits do not change this history.</p></details></div><div className="media-tools"><RemixComposer post={post} adminName={adminName}/>{post.can_manage ? <MediaEditor key={post.id} post={post}/> : <section className="media-editor"><h2>Protected post</h2><p>Only the superadmin can edit or delete this post.</p><h3>Private context</h3><p>{post.context || 'No context saved.'}</p></section>}</div></div></>}
  </main></AdminShell>;
}
