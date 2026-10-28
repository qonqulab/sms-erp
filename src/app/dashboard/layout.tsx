'use client';

import Link from 'next/link';
import { usePathname, useRouter } from 'next/navigation';
import { useEffect, useState, useCallback } from 'react';
import { useAuth } from '@/hooks/useAuth';
import { useHeartbeat } from '@/hooks/useHeartbeat';
import { authService } from '@/lib/services/auth-service';
import { canAccessRoute } from '@/lib/permissions';
import { chatService } from '@/lib/services/chat-service';

import { Sidebar } from '@/components/dashboard/Sidebar';
import { NotificationBell } from '@/components/ui/NotificationBell';
import { ChatPanel } from '@/components/chat/ChatPanel';
import BranchIndicator from '@/components/layout/BranchIndicator';
import { getNavigationForProfile } from '@/lib/navigation';
import { PageSpinner } from '@/components/ui/LoadingSkeleton';

export default function DashboardLayout({ children }: { children: React.ReactNode }) {
  const { profile, loading, role } = useAuth();
  useHeartbeat(profile?.id);
  const router = useRouter();
  const pathname = usePathname();
  const [sidebarOpen, setSidebarOpen] = useState(false);
  const [chatOpen, setChatOpen] = useState(false);
  const [isChatAnimating, setIsChatAnimating] = useState(false);

  const toggleChat = useCallback(() => {
    if (isChatAnimating) return;
    setIsChatAnimating(true);
    setChatOpen(prev => !prev);
    setTimeout(() => setIsChatAnimating(false), 350);
  }, [isChatAnimating]);

  // Auth redirect
  useEffect(() => {
    if (!loading && !profile) {
      router.push('/login');
    }
  }, [loading, profile, router]);

  // Route guard — now feature-based
  useEffect(() => {
    if (loading || !profile) return;
    if (pathname === '/dashboard') return;
    if (pathname === '/dashboard/profile') return;

    const hasDirectAccess = canAccessRoute(profile, pathname);
    const visibleNav = getNavigationForProfile(profile);
    const hasNestedAccess = visibleNav.some(
      item => pathname.startsWith(item.href + '/') && canAccessRoute(profile, item.href)
    );

    if (!hasDirectAccess && !hasNestedAccess) {
      router.replace(authService.getRoleRedirect(profile.role));
    }
  }, [loading, pathname, profile, router]);

  // Close sidebar on route change
  useEffect(() => {
    setSidebarOpen(false);
  }, [pathname]);

  const canChat = profile?.role ? chatService.canUseChat(profile.role) : false;

  const visibleNav = getNavigationForProfile(profile);
  const activeNavItem = [...visibleNav]
    .sort((a, b) => b.href.length - a.href.length)
    .find(
      (item) =>
        pathname === item.href ||
        (item.href !== '/dashboard' && pathname.startsWith(item.href + '/'))
    );
  
  const currentPageLabel = activeNavItem?.label ?? 'Dashboard';

  if (loading) return <PageSpinner />;
  if (!profile) return null;

  return (
    <div className="flex min-h-screen bg-[var(--apple-gray-bg)] text-[var(--apple-text-primary)] antialiased">
      {/* Mobile backdrop */}
      {sidebarOpen && (
        <div
          className="fixed inset-0 z-[35] bg-black/30 transition-opacity lg:hidden"
          onClick={() => setSidebarOpen(false)}
          aria-hidden="true"
        />
      )}

      <Sidebar isOpen={sidebarOpen} onClose={() => setSidebarOpen(false)} />

      <div className="flex h-screen min-w-0 flex-1 flex-col overflow-hidden">
        {/* Top bar */}
        <header className="sticky top-0 z-30 flex h-14 items-center justify-between border-b border-[var(--apple-gray-border)] bg-white px-4 sm:px-6">
          <div className="flex items-center gap-3">
            <button
              className="rounded-lg px-2 py-1.5 text-xs font-medium text-gray-600 transition-colors hover:bg-gray-100 lg:hidden"
              onClick={() => setSidebarOpen(true)}
              aria-label="Open menu"
            >
              Menu
            </button>
            <h2 className="hidden text-sm font-semibold tracking-tight sm:block">
              {currentPageLabel}
            </h2>
            <BranchIndicator />
          </div>

          <div className="flex items-center gap-1">
            <NotificationBell />

            {canChat && (
              <button
                onClick={toggleChat}
                disabled={isChatAnimating}
                className={`relative rounded-lg px-2 py-1.5 text-xs font-medium transition-colors ${isChatAnimating ? 'text-gray-400 cursor-default' : 'text-gray-600 hover:bg-gray-100 hover:text-gray-900 dark:text-gray-400 dark:hover:bg-gray-800'}`}
                aria-label="Toggle chat"
              >
                Chat
              </button>
            )}

            <div className="ml-1 flex h-8 w-8 items-center justify-center rounded-full bg-blue-50 text-xs font-bold uppercase text-blue-600 ring-1 ring-blue-100">
              {(profile.name ?? profile.email ?? 'U')[0]}
            </div>
          </div>
        </header>

        {/* Main content */}
        <main className="custom-scrollbar flex-1 overflow-y-auto bg-white p-4 sm:p-6 lg:p-8">
          <div className="mx-auto max-w-7xl">
            {children}
          </div>
        </main>
      </div>

      {/* Chat panel */}
      <ChatPanel isOpen={chatOpen} onClose={() => setChatOpen(false)} />
    </div>
  );
}
