import assert from 'node:assert/strict';

// Run against the local dev server; no authenticated data or live writes.
const origin = 'http://localhost:3001';
const checks = [
  ['/', 'GET', 307], ['/login', 'GET', 200],
  ['/api/admin/session', 'GET', 401], ['/users', 'GET', 307],
  ['/users/c679baab-8190-4376-9f76-a0fb9bb25cb0', 'GET', 307],
  ['/api/admin/users/c679baab-8190-4376-9f76-a0fb9bb25cb0/image', 'GET', 401],
  ['/api/admin/users/c679baab-8190-4376-9f76-a0fb9bb25cb0/superadmin', 'PUT', 401],
  ['/media', 'GET', 307],
  ['/ratings', 'GET', 307],
  ['/ratings?direction=down', 'GET', 307],
  ['/media/842e05d8-b0ef-4407-bb41-0c84864ced29', 'GET', 307],
  ['/api/admin/media/842e05d8-b0ef-4407-bb41-0c84864ced29', 'PATCH', 401],
  ['/api/admin/media/842e05d8-b0ef-4407-bb41-0c84864ced29', 'DELETE', 401],
  ['/reports.csv', 'GET', 307], ['/auth/callback', 'GET', 307],
  ['/auth/signout', 'POST', 403], ['/auth/google', 'POST', 403],
  ['/auth/google', 'GET', 405],
];
for (const [path, method, status] of checks) {
  const response = await fetch(origin + path, {
    method, redirect: 'manual',
    headers: method === 'POST' ? { Origin: 'https://untrusted.example' } : {},
  });
  assert.equal(response.status, status, `${method} ${path}`);
  if (['/', '/users', '/media', '/reports.csv'].includes(path)) {
    assert.equal(new URL(response.headers.get('location'), origin).pathname, '/login');
  }
  if (path === '/api/admin/session') {
    assert.match(response.headers.get('cache-control'), /no-store/);
  }
  console.log(`${method} ${path}: ${status} OK`);
}
