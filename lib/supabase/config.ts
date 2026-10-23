import { trustedRequestOrigin } from '@/lib/auth/origin';

export function supabaseConfig() {
  const url = process.env.NEXT_PUBLIC_SUPABASE_URL;
  const key = process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY;
  if (!url || !key) throw new Error('Supabase environment variables are missing.');
  return { url, key };
}

// Separate from the main app, including when both run on localhost.
export const cookieOptions = {
  name: 'humour-admin-auth',
  httpOnly: true,
  sameSite: 'lax' as const,
  secure: process.env.NODE_ENV === 'production',
  path: '/',
};

export function appOrigin(request: Pick<Request, 'url'>) {
  return trustedRequestOrigin(request.url, {
    appUrl: process.env.APP_URL,
    vercelUrl: process.env.VERCEL_URL,
    allowLocalhost: process.env.NODE_ENV !== 'production',
  });
}
