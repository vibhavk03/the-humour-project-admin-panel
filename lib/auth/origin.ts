type OriginConfig = { appUrl?: string; vercelUrl?: string; allowLocalhost: boolean };

/** Resolve only exact origins from server-owned configuration, never headers. */
export function trustedRequestOrigin(requestUrl: string, config: OriginConfig): string | null {
  const allowed = new Set<string>();
  if (config.appUrl) {
    try {
      const url = new URL(config.appUrl);
      const local = config.allowLocalhost && url.protocol === 'http:' && url.hostname === 'localhost';
      if ((url.protocol === 'https:' || local) && !url.username && !url.password &&
          url.pathname === '/' && !url.search && !url.hash) allowed.add(url.origin);
    } catch { /* Invalid configuration never becomes a trusted origin. */ }
  }
  // Vercel supplies the deployment hostname without a scheme or path.
  if (config.vercelUrl && /^[a-z0-9](?:[a-z0-9-]*[a-z0-9])?\.vercel\.app$/i.test(config.vercelUrl)) {
    allowed.add(`https://${config.vercelUrl.toLowerCase()}`);
  }
  try {
    const request = new URL(requestUrl);
    if (request.username || request.password) return null;
    return allowed.has(request.origin) ? request.origin : null;
  } catch {
    return null;
  }
}
