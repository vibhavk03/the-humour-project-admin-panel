import assert from 'node:assert/strict';
import { test } from 'node:test';
import sharp from 'sharp';
import { generateRemix, parseCaptions, imageBytes, validateRemixInput } from '../lib/remix/generate.ts';

const completed = (text: string) => ({ status: 'completed', output: [{ type: 'message', content: [{ type: 'output_text', text }] }] });

test('caption parser rejects refusals, incomplete output and invalid/oversized captions', () => {
  assert.deepEqual(parseCaptions(completed(JSON.stringify({ captions: ['A brand new joke.', 'Another new joke.', 'A third new joke.'] }))), ['A brand new joke.', 'Another new joke.', 'A third new joke.']);
  for (const value of [{ caption: 'Old shape' }, { captions: ['Only one'] }, { captions: ['One', 'Two'] }, { captions: ['One', 'Two', 'Three', 'Four'] }, { captions: ['One', 'Two', ''] }, { captions: ['One', 'Two', 'x'.repeat(201)] }, { captions: ['One', 'Two', 'two\nlines'] }, { captions: ['Same', ' same ', 'Different'] }, { captions: ['One', 'Two', null] }]) {
    assert.throws(() => parseCaptions(completed(JSON.stringify(value))), /three distinct usable captions/);
  }
  assert.throws(() => parseCaptions({ ...completed('{}'), status: 'incomplete' }), /did not finish/);
  assert.throws(() => parseCaptions({ status: 'completed', output: [{ type: 'message', content: [{ type: 'refusal' }] }] }), /could not caption/);
});

test('reject malformed IDs and unbounded prompt/context input before database or paid calls', () => {
  const valid = { requestId: '30000000-0000-0000-0000-000000000001', prompt: 'Write a caption', context: '' };
  assert.equal(validateRemixInput(valid), true);
  for (const value of [null, { ...valid, requestId: 'not-an-id' }, { ...valid, prompt: ' ' }, { ...valid, prompt: 'x'.repeat(12001) }, { ...valid, context: 'x'.repeat(1001) }]) {
    assert.equal(validateRemixInput(value), false);
  }
});

test('private image input rejects empty, unsupported and oversized uploads', async () => {
  await assert.rejects(imageBytes(new Blob([], { type: 'image/png' })), /source must/);
  await assert.rejects(imageBytes(new Blob(['text'], { type: 'text/html' })), /source must/);
  await assert.rejects(imageBytes(new Blob([new Uint8Array(5 * 1024 * 1024 + 1)], { type: 'image/png' })), /source must/);
});

test('vision request uses the edited prompt, image bytes, context and strict three-caption output', async t => {
  const originalKey = process.env.OPENAI_API_KEY;
  process.env.OPENAI_API_KEY = 'test-only-key';
  t.after(() => { if (originalKey === undefined) delete process.env.OPENAI_API_KEY; else process.env.OPENAI_API_KEY = originalKey; });
  const bytes = await sharp({ create: { width: 2, height: 2, channels: 3, background: '#aabbcc' } }).png().toBuffer();
  let calls = 0;
  t.mock.method(globalThis, 'fetch', async (url: string, options: RequestInit) => {
    calls++;
    assert.equal(url, 'https://api.openai.com/v1/responses');
    const body = JSON.parse(String(options.body));
    assert.ok(body.instructions.startsWith('Make this joke about exams.'));
    assert.equal(body.store, false);
    assert.equal(body.text.format.type, 'json_schema');
    assert.equal(body.text.format.strict, true);
    assert.equal(body.text.format.schema.properties.captions.minItems, 3);
    assert.equal(body.text.format.schema.properties.captions.maxItems, 3);
    assert.match(body.instructions, /exactly three distinct/);
    assert.match(body.input[0].content[0].text, /Quiet library/);
    assert.match(body.input[0].content[1].image_url, /^data:image\/png;base64,/);
    return Response.json({ ...completed(JSON.stringify({ captions: ['My study plan has entered witness protection.', 'The library has seen enough of me.', 'My notes filed for a transfer.'] })), model: 'test-model', id: 'resp-test' });
  });
  const result = await generateRemix(bytes, 'Make this joke about exams.', 'Quiet library');
  assert.deepEqual(result.captions, ['My study plan has entered witness protection.', 'The library has seen enough of me.', 'My notes filed for a transfer.']);
  assert.equal(result.model, 'test-model'); assert.equal(result.responseId, 'resp-test'); assert.equal(calls, 1);
});

test('GIF input is converted for vision without mutating the original, and quota errors are actionable', async t => {
  const originalKey = process.env.OPENAI_API_KEY;
  process.env.OPENAI_API_KEY = 'test-only-key';
  t.after(() => { if (originalKey === undefined) delete process.env.OPENAI_API_KEY; else process.env.OPENAI_API_KEY = originalKey; });
  const bytes = await sharp({ create: { width: 2, height: 2, channels: 3, background: 'red' } }).gif().toBuffer();
  const before = Buffer.from(bytes);
  t.mock.method(globalThis, 'fetch', async (_url: string, options: RequestInit) => {
    const body = JSON.parse(String(options.body));
    const sent = Buffer.from(body.input[0].content[1].image_url.split(',')[1], 'base64');
    assert.equal((await sharp(sent).metadata()).format, 'png');
    return Response.json({ error: { code: 'insufficient_quota' } }, { status: 429 });
  });
  await assert.rejects(generateRemix(bytes, 'Prompt', ''), /credit limit/);
  assert.deepEqual(bytes, before);
});

test('more-caption requests send previous choices and reject a repeated result', async t => {
  const originalKey = process.env.OPENAI_API_KEY;
  process.env.OPENAI_API_KEY = 'test-only-key';
  t.after(() => { if (originalKey === undefined) delete process.env.OPENAI_API_KEY; else process.env.OPENAI_API_KEY = originalKey; });
  const bytes = await sharp({ create: { width: 2, height: 2, channels: 3, background: 'red' } }).png().toBuffer();
  t.mock.method(globalThis, 'fetch', async (_url: string, options: RequestInit) => {
    const body = JSON.parse(String(options.body));
    assert.match(body.input[0].content.find((item: { text?: string }) => item.text?.includes('Previously offered')).text, /Already offered/);
    return Response.json({ ...completed(JSON.stringify({ captions: [' Already offered ', 'Fresh joke two', 'Fresh joke three'] })), model: 'test-model', id: 'resp-test' });
  });
  await assert.rejects(generateRemix(bytes, 'Prompt', '', ['Already offered']), /repeated a previous caption/);
});
