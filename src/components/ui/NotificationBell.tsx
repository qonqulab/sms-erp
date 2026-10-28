'use client';

import { useEffect, useState, useCallback } from 'react';
import { useAuth } from '@/hooks/useAuth';
import { notificationService } from '@/lib/services/notification-service';
import { useRouter } from 'next/navigation';
import { useRealtimeTable } from '@/hooks/useRealtimeTable';

export function NotificationBell() {
  const { profile } = useAuth();
  const router = useRouter();
  const [count, setCount] = useState(0);

  const fetchCount = useCallback(async () => {
    if (!profile?.id) return;
    try {
      const c = await notificationService.getUnreadCount(profile.id);
      setCount(c);
    } catch {
      // Silently fail — non-critical
    }
  }, [profile?.id]);

  useEffect(() => {
    fetchCount();
  }, [fetchCount]);

  // Re-fetch count on any notification change (INSERT, UPDATE, DELETE)
  useRealtimeTable(
    'notifications',
    profile?.id ? `user_id=eq.${profile.id}` : undefined,
    fetchCount,
    { enabled: Boolean(profile?.id), debounceMs: 300 },
  );

  return (
    <button
      onClick={() => router.push('/dashboard/notifications')}
      className="relative rounded-lg px-2.5 py-2 text-xs font-medium text-[var(--apple-text-secondary)] transition-colors hover:bg-[var(--apple-gray-bg)] hover:text-[var(--apple-text-primary)]"
      aria-label={`Notifications${count > 0 ? `, ${count} unread` : ''}`}
    >
      Alerts
      {count > 0 && (
        <span className="absolute -right-1 -top-1 flex h-4 min-w-4 items-center justify-center rounded-full bg-[var(--apple-danger)] px-1 text-[9px] font-bold text-white">
          {count > 99 ? '99+' : count}
        </span>
      )}
    </button>
  );
}
