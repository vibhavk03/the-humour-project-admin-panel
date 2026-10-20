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

export function appOrigin() {
  const value = process.env.APP_URL;
  if (!value) throw new Error('APP_URL is required.');
  const url = new URL(value);
  if (url.protocol !== 'https:' && !(url.protocol === 'http:' && url.hostname === 'localhost')) {
    throw new Error('APP_URL must use HTTPS (or localhost for development).');
  }
  return url.origin;
}
