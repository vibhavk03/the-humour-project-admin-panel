import type { SupabaseClient, User } from '@supabase/supabase-js';

export type Access =
  | { status: 'allowed'; user: User; role: 'superadmin' | 'admin' }
  | { status: 'signed-out' | 'denied' | 'unavailable' };

export async function checkAdmin(client: SupabaseClient): Promise<Access> {
  try {
    // Always ask Auth; never trust a cookie's user payload or getSession().
    const { data: { user }, error } = await client.auth.getUser();
    if (error || !user) return { status: 'signed-out' };
    if (user.app_metadata.provider !== 'google') return { status: 'denied' };
    const { data: profile, error: profileError } = await client.from('profiles')
      .select('is_superadmin,is_admin').eq('id', user.id).maybeSingle();
    if (profileError) return { status: 'unavailable' };
    if (profile?.is_superadmin !== true && profile?.is_admin !== true) return { status: 'denied' };
    return { status: 'allowed', user, role: profile.is_superadmin === true ? 'superadmin' : 'admin' };
  } catch {
    return { status: 'unavailable' };
  }
}
