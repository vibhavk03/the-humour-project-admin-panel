import assert from 'node:assert/strict';
import { test } from 'node:test';
import { trustedRequestOrigin } from '../lib/auth/origin.ts';

const stable = 'https://the-humour-project-admin-panel.vercel.app';
const deployment = 'the-humour-project-admin-panel-7xm8zmzu0.vercel.app';
const config = { appUrl: stable, vercelUrl: deployment, allowLocalhost: false };

test('deployment works without APP_URL and keeps callbacks on its exact origin', () => {
  assert.equal(trustedRequestOrigin(`https://${deployment}/auth/google`, { vercelUrl: deployment, allowLocalhost: false }), `https://${deployment}`);
  assert.equal(trustedRequestOrigin(`https://${deployment}/auth/callback?code=example`, config), `https://${deployment}`);
});
test('stable domain and deployment each resolve to their own origin', () => {
  assert.equal(trustedRequestOrigin(`${stable}/auth/google`, config), stable);
  assert.equal(trustedRequestOrigin(`https://${deployment}/auth/google`, config), `https://${deployment}`);
});
test('other deployments, branch aliases and lookalike domains are rejected unless configured', () => {
  for (const origin of ['https://untrusted.vercel.app', `${stable}.evil.example`, 'https://the-humour-project-admin-pa-git-other.vercel.app', 'http://' + deployment]) {
    assert.equal(trustedRequestOrigin(`${origin}/auth/google`, config), null);
  }
});
test('an exact configured branch alias is supported', () => {
  const branch = 'https://project-git-main-team.vercel.app';
  assert.equal(trustedRequestOrigin(`${branch}/auth/google`, { ...config, appUrl: branch }), branch);
});
test('localhost must be explicitly configured and enabled for development', () => {
  const local = { appUrl: 'http://localhost:3001', allowLocalhost: true };
  assert.equal(trustedRequestOrigin('http://localhost:3001/auth/google', local), 'http://localhost:3001');
  assert.equal(trustedRequestOrigin('http://localhost:3000/auth/google', local), null);
  assert.equal(trustedRequestOrigin('http://localhost:3001/auth/google', { ...local, allowLocalhost: false }), null);
});
test('missing or malformed configuration fails closed', () => {
  assert.equal(trustedRequestOrigin(`${stable}/auth/google`, { allowLocalhost: false }), null);
  for (const appUrl of ['not a URL', stable + '/auth/callback', stable + '?next=evil', 'https://name:password@the-humour-project-admin-panel.vercel.app']) {
    assert.equal(trustedRequestOrigin(`${stable}/auth/google`, { appUrl, allowLocalhost: false }), null);
  }
  for (const vercelUrl of ['https://' + deployment, deployment + '/path', deployment + '@evil.example', deployment + ':443', deployment + '.evil.example']) {
    assert.equal(trustedRequestOrigin(`https://${deployment}/auth/google`, { vercelUrl, allowLocalhost: false }), null);
  }
});
test('malformed incoming URLs and URL credentials are rejected', () => {
  assert.equal(trustedRequestOrigin('not a URL', config), null);
  assert.equal(trustedRequestOrigin(`https://username@${deployment}/auth/google`, config), null);
});
