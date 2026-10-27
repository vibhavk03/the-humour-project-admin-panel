import { createHash } from 'node:crypto';
import { NextResponse } from 'next/server';
import { generateRemix, imageBytes, RemixError, validateRemixInput } from '@/lib/remix/generate';
import { databaseFailure, failure, privateHeaders, remixAccess } from '@/lib/remix/http';
import { publicRemix, type RemixJob } from '@/lib/remix/types';
import { createClient } from '@/lib/supabase/server';
import { checkAdmin } from '@/lib/auth/check';
import { validUserId } from '@/lib/users/types';

export const runtime = 'nodejs';
export const maxDuration = 60;

export async function POST(request: Request, { params }: { params: Promise<{ id: string }> }) {
  const access = await remixAccess(request);
  if ('response' in access) return access.response;
  const { client } = access;
  const { id } = await params;
  const body: unknown = await request.json().catch(() => null);
  if (!validUserId(id) || !validateRemixInput(body)) return failure('Send a valid request ID, prompt (1–12,000 characters) and context (up to 1,000 characters).', 400);
  if (!process.env.OPENAI_API_KEY) return failure('Caption generation is not configured. Set OPENAI_API_KEY on the server.', 503);
  const { data, error } = await client.rpc('admin_remix_begin_batch', {
    target_id: id, request_id: body.requestId, edited_prompt: body.prompt, image_context: body.context, previous_request_id: body.sessionId ?? null,
  });
  if (error) return databaseFailure(error);
  const job = data as RemixJob;
  // A retry can recover a finished preview without making a second paid AI call.
  if (!job.claimed) return NextResponse.json({ remix: publicRemix(job) }, { headers: privateHeaders });
  try {
    const { data: image, error: imageError } = await client.storage.from('post-images').download(job.source_image_path);
    if (imageError || !image) throw new RemixError('The source image is unavailable. No post was changed.', 404);
    const bytes = await imageBytes(image);
    const generated = await generateRemix(bytes, job.prompt, job.context, (job.session_captions ?? []).map(option => option.caption));
    const { data: saved, error: saveError } = await client.rpc('admin_remix_finish', {
      request_id: job.id, caption_value: JSON.stringify(generated.captions), model_value: generated.model,
      response_id: generated.responseId, image_hash: createHash('sha256').update(bytes).digest('hex'), failure_message: null,
    });
    if (saveError) {
      if (saveError.code === '22023') throw new RemixError(saveError.message, 422);
      return databaseFailure(saveError);
    }
    return NextResponse.json({ remix: publicRemix(saved as RemixJob) }, { headers: privateHeaders });
  } catch (error) {
    const message = error instanceof RemixError ? error.message : 'Caption generation failed. Please try again.';
    await client.rpc('admin_remix_finish', { request_id: job.id, caption_value: null, model_value: null, response_id: null, image_hash: null, failure_message: message });
    return failure(message, error instanceof RemixError ? error.status : 502);
  }
}

export async function GET(_request: Request, { params }: { params: Promise<{ id: string }> }) {
  const client = await createClient();
  const access = await checkAdmin(client);
  if (access.status !== 'allowed') return failure('Admin access required', access.status === 'signed-out' ? 401 : access.status === 'denied' ? 403 : 503);
  const { id } = await params;
  if (!validUserId(id)) return failure('Invalid post ID', 400);
  const { data, error } = await client.rpc('admin_remix_history', { target_id: id });
  if (error) return databaseFailure(error);
  return NextResponse.json({ remixes: (data as RemixJob[]).map(publicRemix) }, { headers: privateHeaders });
}
