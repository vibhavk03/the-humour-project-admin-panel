'use client';
import { useState } from 'react';
export function ProfilePostImage({ userId, postId }: { userId: string; postId: string }) {
  const [failed, setFailed] = useState(false);
  return <div className="profile-post-image">{failed ? <span>Image unavailable</span> : /* eslint-disable-next-line @next/next/no-img-element */
    <img src={`/api/admin/users/${userId}/image?post=${postId}`} alt="Post image" loading="lazy" onError={() => setFailed(true)} />}</div>;
}
