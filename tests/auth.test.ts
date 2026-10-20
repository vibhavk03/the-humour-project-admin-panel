import assert from 'node:assert/strict';
import { test } from 'node:test';
import type { SupabaseClient, User } from '@supabase/supabase-js';
import { checkAdmin } from '../lib/auth/check.ts';

const googleUser = { id: 'verified-user', app_metadata: { provider: 'google' } } as User;
function mockClient({ user = googleUser as User | null, authError = false, flag = true as unknown, profileError = false, throws = false } = {}) {
  let checkedId: string | undefined;
  let queriedProfile = false;
  const client = {
    auth: { getUser: async () => {
      if (throws) throw new Error('Network failure');
      return { data: { user }, error: authError ? new Error('Invalid token') : null };
    } },
    from: (table: string) => {
      queriedProfile = true;
      assert.equal(table, 'profiles');
      return { select: (columns: string) => {
        assert.equal(columns, 'is_superadmin');
        return { eq: (column: string, id: string) => {
          assert.equal(column, 'id');
          checkedId = id;
          return { maybeSingle: async () => ({ data: flag === null ? null : { is_superadmin: flag }, error: profileError ? new Error('Database failure') : null }) };
        } };
      } };
    },
  } as unknown as SupabaseClient;
  return { client, checkedId: () => checkedId, queriedProfile: () => queriedProfile };
}

test('only a verified Google user with the boolean database flag is allowed', async () => {
  const fixture = mockClient();
  assert.equal((await checkAdmin(fixture.client)).status, 'allowed');
  assert.equal(fixture.checkedId(), googleUser.id);
});
test('missing or rejected sessions cannot query admin permissions', async () => {
  for (const options of [{ user: null }, { authError: true }]) {
    const fixture = mockClient(options);
    assert.equal((await checkAdmin(fixture.client)).status, 'signed-out');
    assert.equal(fixture.queriedProfile(), false);
  }
});
test('a non-Google login is denied even with a Google identity linked', async () => {
  const fixture = mockClient({ user: { ...googleUser, app_metadata: { provider: 'email', providers: ['email', 'google'] } } });
  assert.equal((await checkAdmin(fixture.client)).status, 'denied');
});
test('false, missing and truthy non-boolean flags are denied', async () => {
  for (const flag of [false, null, undefined, 'true', 1]) {
    const fixture = mockClient({ flag: flag === undefined ? 'undefined' : flag });
    assert.equal((await checkAdmin(fixture.client)).status, 'denied');
  }
});
test('database errors and network failures fail closed', async () => {
  for (const options of [{ profileError: true }, { throws: true }]) {
    assert.equal((await checkAdmin(mockClient(options).client)).status, 'unavailable');
  }
});
test('revoking the flag is observed on the next check', async () => {
  assert.equal((await checkAdmin(mockClient({ flag: true }).client)).status, 'allowed');
  assert.equal((await checkAdmin(mockClient({ flag: false }).client)).status, 'denied');
});
