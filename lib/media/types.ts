export type MediaPost = { id:string; user_id:string; caption:string|null; created_at:string; author_name:string|null; upvotes:number; downvotes:number };
export type MediaList = { posts:MediaPost[]; total:number; page:number; pageSize:number };
export type MediaDetail = MediaPost & { can_manage:boolean; context:string|null; generation_prompt:string|null; prompt_version:string|null; model:string|null; version:string };
