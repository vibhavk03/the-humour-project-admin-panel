'use client';
import Link from 'next/link';
import { useEffect, useState } from 'react';
import type { MediaDetail } from '@/lib/media/types';
import { DEFAULT_REMIX_PROMPT, type publicRemix } from '@/lib/remix/types';

type Preview = ReturnType<typeof publicRemix>;
type RequestDraft = { requestId: string; prompt: string; context: string; sessionId?: string };

export function RemixComposer({ post, adminName }: { post: MediaDetail; adminName: string }) {
  const [open, setOpen] = useState(false);
  const [prompt, setPrompt] = useState(post.generation_prompt || DEFAULT_REMIX_PROMPT);
  const [context, setContext] = useState(post.context || '');
  const [preview, setPreview] = useState<Preview | null>(null);
  const [caption, setCaption] = useState('');
  const [selectedIndex, setSelectedIndex] = useState(0);
  const [history, setHistory] = useState<Preview[]>([]);
  const [pending, setPending] = useState<RequestDraft | null>(null);
  const [busy, setBusy] = useState<'generate' | 'publish' | null>(null);
  const [message, setMessage] = useState('');
  const [error, setError] = useState('');
  const [postId, setPostId] = useState('');
  const changed = !!preview && (prompt.trim() !== preview.prompt || context.trim() !== preview.context);
  const sameSession = !!preview && !changed && !postId && preview.captions.length > 0 && preview.captions.length % 3 === 0;
  const atLimit = sameSession && preview.captions.length >= 15;
  useEffect(() => {
    if (!open) return;
    const controller = new AbortController();
    fetch(`/api/admin/media/${post.id}/remix`, { signal: controller.signal })
      .then(async response => { const result = await response.json(); if (response.ok) setHistory(result.remixes); else setError(result.error || 'Could not load your previews.'); })
      .catch(() => { if (!controller.signal.aborted) setError('Could not load your previews. Try reopening this section.'); });
    return () => controller.abort();
  }, [open, post.id]);

  function selectPreview(result: Preview) {
    setSelectedIndex(result.captions.indexOf(result.caption || ''));
    setPreview(result); setCaption(result.caption || ''); setPrompt(result.prompt); setContext(result.context);
    setPostId(result.postId || ''); setPending(null); setError(''); setMessage('');
  }
  async function generate(recover = false) {
    if (!recover && atLimit) return;
    const draft: RequestDraft = recover && pending ? pending : { requestId: crypto.randomUUID(), prompt, context, ...(sameSession ? { sessionId: preview.sessionId } : {}) };
    setPending(draft); setBusy('generate'); setMessage(''); setError('');
    try {
      const response = await fetch(`/api/admin/media/${post.id}/remix`, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(draft) });
      const result = await response.json();
      if (!response.ok) throw new Error(result.error || 'Could not generate a caption.');
      const job: Preview = result.remix;
      if (job.status === 'generating') { setMessage('This request is still processing. Use “Check last request” to recover its result without another AI call.'); return; }
      if (job.status === 'failed') { setPending(null); throw new Error(job.error || 'Generation failed. Try again.'); }
      if (preview && job.sessionId === preview.sessionId && job.status !== 'published') {
        setPreview(job); setPending(null);
      } else selectPreview(job);
      setHistory(current => [job, ...current.filter(item => item.sessionId !== job.sessionId)].slice(0, 10));
      setMessage(`${job.captions.length} caption${job.captions.length === 1 ? '' : 's'} ready. Choose your favorite, then review it before publishing.`);
    } catch (error) { setError(error instanceof Error ? error.message : 'Could not generate a caption.'); }
    finally { setBusy(null); }
  }
  async function publish() {
    if (!preview) return;
    setBusy('publish'); setMessage(''); setError('');
    try {
      const response = await fetch(`/api/admin/remixes/${preview.options[selectedIndex]?.requestId || preview.id}/publish`, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ caption }) });
      const result = await response.json();
      if (!response.ok) throw new Error(result.error || 'Could not publish. Retry to recover this same post.');
      setPostId(result.postId); setMessage(`Published as ${adminName}. The source post is unchanged.`);
      setPreview(current => current ? { ...current, status: 'published', postId: result.postId, caption } : current);
      setHistory(current => current.map(item => item.sessionId === preview.sessionId ? { ...item, status: 'published', postId: result.postId, caption } : item));
    } catch (error) { setError(error instanceof Error ? error.message : 'Could not publish.'); }
    finally { setBusy(null); }
  }
  return <section className="media-editor remix-composer">
    <span className="eyebrow">A NEW TAKE</span><h2>Remix with AI.</h2>
    <p className="editor-intro">Use this image and an edited prompt to create your own post. The source post, caption and votes stay unchanged.</p>
    {!open ? <button type="button" className="primary-button" onClick={() => setOpen(true)}>Create a remix ↗</button> : <>
      <div className="remix-author"><span>Publishing as</span><strong>{adminName}</strong><small>A separate post with its own image copy and zero votes.</small></div>
      <label htmlFor="remix-prompt">Generation prompt <span>{prompt.length}/12000</span></label>
      <textarea id="remix-prompt" rows={7} maxLength={12000} value={prompt} disabled={!!busy} onChange={event => setPrompt(event.target.value)} />
      <label htmlFor="remix-context">Context for this remix <span>{context.length}/1000</span></label>
      <textarea id="remix-context" rows={3} maxLength={1000} value={context} disabled={!!busy} onChange={event => setContext(event.target.value)} />
      <p className="field-note">Context is sent to the AI, but is not shown in the public feed. GIFs use their first frame for generation; the published copy keeps the animation.</p>
      <div className="editor-actions"><button type="button" className="primary-button" disabled={!!busy || !prompt.trim() || atLimit} onClick={() => generate()}>{busy === 'generate' ? 'Generating…' : atLimit ? '15-caption limit reached' : sameSession ? 'Generate 3 more captions' : 'Generate 3 captions'}</button>{pending && <button type="button" className="refresh-link" disabled={!!busy} onClick={() => generate(true)}>Check last request</button>}</div>
      {preview && <div className="remix-progress"><span>{preview.captions.length} / 15 captions</span><span>{postId ? 'Published' : changed ? 'New prompt starts a new set' : atLimit ? 'All 15 choices ready' : `${15 - preview.captions.length} remaining`}</span><progress value={preview.captions.length} max={15} aria-label="Captions generated in this remix" /></div>}
      {preview && <div className="remix-preview"><span className="eyebrow">CAPTION PREVIEW</span><p className="field-note">Source caption</p><blockquote>{post.caption || 'No caption saved.'}</blockquote>
        <fieldset className="remix-choices" disabled={!!busy || !!postId}><legend>Choose a caption</legend>
          {preview.captions.map((choice, index) => <label className={`remix-choice${selectedIndex === index ? ' selected' : ''}`} key={index}>
            <input type="radio" name="remix-caption-choice" value={index} checked={selectedIndex === index} onChange={() => { setSelectedIndex(index); setCaption(choice); }} />
            <span><small>OPTION {index + 1}</small>{choice}</span>
          </label>)}
        </fieldset>
        {preview.captions.length === 1 && <p className="field-note">This older preview has one saved caption. Generate again to get three choices.</p>}
        <label htmlFor="remix-caption">Your selected caption <span>{caption.length}/200</span></label><textarea id="remix-caption" rows={4} maxLength={200} value={caption} disabled={!!busy || !!postId} onChange={event => setCaption(event.target.value)} />
        <p className="field-note">Generated with {preview.options[selectedIndex]?.model || preview.model || 'the configured model'}. You can refine the caption before publishing.</p>
        {changed && !postId && <p className="field-note">The prompt or context changed after this preview. Generate to start a new set of up to 15 captions, or restore this set’s inputs from your history.</p>}
        {postId ? <Link className="remix-post-link" href={`/media/${postId}`}>View your published post ↗</Link> : <button type="button" className="primary-button" disabled={!!busy || changed || !caption.trim()} onClick={publish}>{busy === 'publish' ? 'Publishing…' : `Publish as ${adminName}`}</button>}
      </div>}
      {message && <p className="media-message" role="status">{message}</p>}
      {error && <p className="media-message error" role="alert">{error}</p>}
      {history.length > 0 && <details className="remix-history"><summary>Your recent remixes of this image</summary>{history.map(item => <div key={item.sessionId}><span>{item.status === 'published' ? 'Published' : item.status === 'ready' ? `Preview · ${item.captions.length}/15 captions` : item.status === 'failed' ? 'Failed' : 'Processing'}</span><p>{item.caption || item.error || 'No result saved yet.'}</p>{['ready', 'published'].includes(item.status) && <button type="button" className="refresh-link" disabled={!!busy} onClick={() => selectPreview(item)}>{item.status === 'published' ? 'View result' : 'Restore preview'}</button>}</div>)}</details>}
      <button type="button" className="remix-close" disabled={!!busy} onClick={() => setOpen(false)}>Close remix composer</button>
    </>}
  </section>;
}
