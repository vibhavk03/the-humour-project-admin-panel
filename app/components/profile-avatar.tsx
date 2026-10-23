'use client';
import { useState } from 'react';
export function ProfileAvatar({ id, name, hasAvatar, large = false }: { id: string; name: string; hasAvatar: boolean; large?: boolean }) {
  const [failed, setFailed] = useState(false);
  const initials = name.split(/\s+/).slice(0, 2).map(part => part[0]).join('').toUpperCase();
  return <span className={`profile-avatar${large ? ' large' : ''}`} aria-hidden="true">
    {hasAvatar && !failed ? /* eslint-disable-next-line @next/next/no-img-element */
      <img src={`/api/admin/users/${id}/image`} alt="" loading="lazy" onError={() => setFailed(true)} /> : initials}
  </span>;
}
