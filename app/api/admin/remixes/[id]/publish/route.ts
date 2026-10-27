import { createHash } from 'node:crypto';
import { NextResponse } from 'next/server';
import { revalidatePath } from 'next/cache';
import { imageBytes, RemixError } from '@/lib/remix/generate';
import { databaseFailure, failure, privateHeaders, remixAccess } from '@/lib/remix/http';
import type { RemixJob } from '@/lib/remix/types';
import { validUserId } from '@/lib/users/types';

export const runtime = 'nodejs';
export const maxDuration = 60;
const hash = (bytes: Buffer) => createHash('sha256').update(bytes).digest('hex');

export async function POST(request: Request, { params }: { params: Promise<{ id: string }> }) {
  const access = await remixAccess(request);
  if ('response' in access) return access.response;
  const { client } = access;
  const { id } = await params;
  const body = await request.json().catch(() => null);
  if (!validUserId(id) || typeof body?.caption !== 'string' || !body.caption.trim() || body.caption.length > 200) return failure('Use a caption between 1 and 200 characters.', 400);
  const { data, error } = await client.rpc('admin_remix_get', { request_id: id });
  if (error) return databaseFailure(error);
  if (!data) return failure('Remix not found.', 404);
  const job = data as RemixJob;
  if (job.session_post_id || job.status === 'published') return NextResponse.json({ postId: job.session_post_id || job.id }, { headers: privateHeaders });
  if (job.status !== 'ready') return failure('Generate a caption before publishing.', 409);
  try {
    const bucket = client.storage.from('post-images');
    // Reuse a prior independent copy after a lost response / database interruption.
    const { data: existing } = await bucket.download(job.image_path);
    if (existing) {
      if (hash(await imageBytes(existing)) !== job.image_sha256) return failure('The image copy does not match this preview. Generate a new remix.', 409);
    } else {
      const { data: source, error: sourceError } = await bucket.download(job.source_image_path);
      if (sourceError || !source) return failure('The source image is no longer available. This preview cannot be published.', 409);
      const bytes = await imageBytes(source);
      if (hash(bytes) !== job.image_sha256) return failure('The source image changed. Generate a fresh preview before publishing.', 409);
      const { error: uploadError } = await bucket.upload(job.image_path, bytes, { contentType: source.type, upsert: false });
      if (uploadError) {
        // A concurrent retry may have copied this same image; never overwrite/delete it.
        const { data: copy } = await bucket.download(job.image_path);
        if (!copy || hash(await imageBytes(copy)) !== job.image_sha256) return failure('Could not copy the image. Retry publishing; the source post is unchanged.', 503);
      }
    }
    const { data: postId, error: publishError } = await client.rpc('admin_remix_publish', { request_id: id, new_caption: body.caption });
    if (publishError) return databaseFailure(publishError);
    revalidatePath('/'); revalidatePath('/media'); revalidatePath('/users');
    return NextResponse.json({ postId }, { status: 201, headers: privateHeaders });
  } catch (error) {
    return failure(error instanceof RemixError ? error.message : 'Publishing could not finish. Retry to recover this same post.', error instanceof RemixError ? error.status : 503);
  }
}
