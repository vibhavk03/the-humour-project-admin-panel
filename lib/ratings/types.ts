export type Rating = {post_id:string;voter_id:string;vote:1|-1;created_at:string;author_id:string;caption:string|null;voter_name:string|null;author_name:string|null};
export type Ratings = {total:number;upvotes:number;downvotes:number;net:number;page:number;pageSize:number;ratings:Rating[]};
export function voteDate(value:string){return new Intl.DateTimeFormat('en-US',{month:'short',day:'numeric',year:'numeric',hour:'numeric',minute:'2-digit',timeZone:'America/New_York',timeZoneName:'short'}).format(new Date(value));}
