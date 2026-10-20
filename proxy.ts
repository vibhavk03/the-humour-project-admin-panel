import { createServerClient } from '@supabase/ssr';
import { NextResponse, type NextRequest } from 'next/server';
import { checkAdmin } from '@/lib/auth/check';
import { cookieOptions, supabaseConfig } from '@/lib/supabase/config';

const publicRoutes = new Set(['/login', '/access-denied', '/auth/google', '/auth/callback', '/auth/signout']);

export async function proxy(request: NextRequest) {
  const pathname = request.nextUrl.pathname;
  if (publicRoutes.has(pathname)) {
    const response = NextResponse.next();
    response.headers.set('Cache-Control', 'private, no-store');
    return response;
  }
  let response = NextResponse.next({ request });
  const { url, key } = supabaseConfig();
  const client = createServerClient(url, key, {
    cookieOptions,
    cookies: {
      getAll: () => request.cookies.getAll(),
      setAll(values) {
        values.forEach(({ name, value }) => request.cookies.set(name, value));
        response = NextResponse.next({ request });
        values.forEach(({ name, value, options }) => response.cookies.set(name, value, options));
      },
    },
  });
  const access = await checkAdmin(client);
  if (access.status !== 'allowed') {
    const denied = pathname.startsWith('/api/')
      ? NextResponse.json({ error: access.status === 'signed-out' ? 'Authentication required' : access.status === 'denied' ? 'Superadmin access required' : 'Could not verify access' },
        { status: access.status === 'signed-out' ? 401 : access.status === 'denied' ? 403 : 503 })
      : NextResponse.redirect(new URL(access.status === 'denied' ? '/access-denied' : access.status === 'unavailable' ? '/login?error=verification' : '/login', request.url));
    response.cookies.getAll().forEach(cookie => denied.cookies.set(cookie));
    response = denied;
  }
  response.headers.set('Cache-Control', 'private, no-store');
  return response;
}

// No file-extension bypass: future admin paths are protected by default.
export const config = { matcher: ['/((?!_next/static|_next/image|favicon.ico).*)'] };
