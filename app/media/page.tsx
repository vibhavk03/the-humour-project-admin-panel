import Link from 'next/link';
import { requireAdmin } from '@/lib/auth/server';
import { AdminShell } from '@/app/components/admin-shell';
import { ProfilePostImage } from '@/app/components/profile-post-image';
import { Pagination } from '@/app/components/pagination';
import { displayDate,pageNumber } from '@/lib/users/types';
import type { MediaList } from '@/lib/media/types';
export default async function Media({searchParams}:{searchParams:Promise<{q?:string;status?:string;page?:string;deleted?:string}>}){
  const {client,user}=await requireAdmin(); const query=await searchParams;
  const q=typeof query.q==='string'?query.q.trim().slice(0,100):''; const status=['published','unpublished'].includes(query.status??'')?query.status!:'all'; const page=pageNumber(query.page);
  const {data,error}=await client.rpc('admin_media_list',{search_query:q,status_filter:status,page_number:page}); const result=!error&&data?data as MediaList:null;
  const href=(next:number)=>`/media?${new URLSearchParams({q,status,page:String(next)})}`;
  return <AdminShell email={user.email} active="media"><main className="pulse-main"><div className="pulse-heading"><div><span className="eyebrow">EVERY PICTURE. EVERY PUNCHLINE.</span><h1>Media<span>.</span></h1><p>Review and manage posts from the whole community.</p></div></div>
    {query.deleted==='1'&&<p className="media-message" role="status">Post, votes, and stored image deleted.</p>}
    <section className="users-panel"><div className="directory-header"><div><h2>The collection.</h2><p>{result?`${result.total} matching posts`:'Community posts'}</p></div><form action="/media" method="get" className="media-search"><label htmlFor="media-search">Search caption, author, or ID</label><div><input id="media-search" name="q" type="search" maxLength={100} defaultValue={q}/><select name="status" aria-label="Post status" defaultValue={status}><option value="all">All posts</option><option value="published">Published</option><option value="unpublished">Unpublished</option></select><button type="submit">Search ↗</button></div></form></div>
    {!result?<div className="users-empty" role="alert"><h3>We couldn’t load the posts.</h3><p>Please refresh and try again.</p></div>:<>{result.posts.length===0?<div className="users-empty"><h3>No posts found.</h3><p>Try another search or status.</p><Link href="/media">Clear filters</Link></div>:<div className="profile-post-grid media-grid">{result.posts.map(post=><article className="profile-post" key={post.id}><Link href={`/media/${post.id}`} aria-label={`Open post by ${post.author_name||'Unnamed contributor'}`}><ProfilePostImage userId={post.user_id} postId={post.id}/></Link><div className="profile-post-body"><div className="post-date"><span>{displayDate(post.created_at)}</span><span className="role-badge">{post.caption!==null?'Published':'Unpublished'}</span></div><Link className="media-author" href={`/users/${post.user_id}`}>{post.author_name||'Unnamed contributor'}</Link><p className="post-caption">{post.caption??'No caption saved.'}</p><div className="post-ratings"><span>↑ {post.upvotes}</span><span>↓ {post.downvotes}</span><strong>Net {post.upvotes-post.downvotes}</strong></div><Link className="media-manage" href={`/media/${post.id}`}>View & manage ↗</Link></div></article>)}</div>}<Pagination page={result.page} total={result.total} pageSize={result.pageSize} href={href} label="Media"/></>}
    </section><p className="users-note">Includes published posts and unpublished uploads. Edits preserve the original author. Dates use America/New_York.</p>
  </main></AdminShell>;
}
