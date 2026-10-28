'use client';

import React from 'react';
import Link from 'next/link';
import { usePathname } from 'next/navigation';
import { useAuth } from '@/hooks/useAuth';
import { getNavigationForProfile } from '@/lib/navigation';

interface SidebarProps {
  isOpen: boolean;
  onClose: () => void;
}

export function Sidebar({ isOpen, onClose }: SidebarProps) {
  const pathname = usePathname();
  const { profile, logout, role } = useAuth();

  if (!profile) return null;

  const visibleNav = getNavigationForProfile(profile);

  const activeItem = React.useMemo(() => {
    return [...visibleNav]
      .sort((a, b) => b.href.length - a.href.length)
      .find(
        (item) =>
          pathname === item.href ||
          (item.href !== '/dashboard' && pathname.startsWith(item.href + '/'))
      );
  }, [pathname, visibleNav]);

  return (
    <aside
      className={`
        fixed left-0 top-0 z-40 flex h-[100dvh] w-[17.5rem] max-w-[calc(100vw-2rem)] flex-col border-r
        border-[var(--apple-gray-border)] bg-white transition-transform duration-200 [transition-timing-function:var(--ease-standard)] lg:static lg:max-w-none lg:translate-x-0
        ${isOpen ? 'translate-x-0' : '-translate-x-full'}
      `}
    >
      {/* Logo */}
      <div className="flex-shrink-0 border-b border-[var(--apple-gray-border)] p-6">
        <Link href="/" className="block" onClick={onClose}>
          <span className="text-base font-semibold tracking-tight text-[var(--apple-text-primary)]">SMS ERP</span>
        </Link>
      </div>

      {/* User info */}
      <div className="flex-shrink-0 border-b border-[var(--apple-gray-border)] bg-white/50 p-4">
        <div className="flex items-center gap-3">
          <div className="flex h-10 w-10 shrink-0 items-center justify-center rounded-full bg-blue-50 text-sm font-bold uppercase text-blue-600">
            {(profile.name ?? profile.email ?? 'U')[0]}
          </div>
          <div className="min-w-0 flex-1">
            <p className="truncate text-sm font-semibold">{profile.name ?? profile.email}</p>
            <span className="mt-0.5 inline-block rounded-full bg-blue-50 px-2 py-0.5 text-[10px] font-bold uppercase tracking-wider text-blue-600">
              {role}
            </span>
          </div>
        </div>
      </div>

      {/* Navigation */}
      <nav className="custom-scrollbar flex-1 overflow-y-auto p-3">
        <div className="space-y-1">
          {visibleNav.map((item) => {
            const isActive = activeItem?.href === item.href;
            return (
              <Link
                key={item.href}
                href={item.href}
                onClick={onClose}
                className={`block rounded-lg px-3 py-2.5 text-sm font-medium transition-colors duration-150 ${
                  isActive ? 'bg-blue-50 text-[var(--apple-blue)]' : 'text-[var(--apple-text-secondary)] hover:bg-gray-50 hover:text-[var(--apple-text-primary)]'
                }`}
              >
                {item.label}
              </Link>
            );
          })}
        </div>
      </nav>

      {/* Sign out */}
      <div className="border-t border-[var(--apple-gray-border)] bg-white/30 p-3">
        <button
          onClick={logout}
          className="flex w-full rounded-lg px-3 py-2.5 text-sm font-medium text-red-600 transition-colors hover:bg-red-50"
        >
          <svg className="h-4 w-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M17 16l4-4m0 0l-4-4m4 4H7m6 4v1a3 3 0 01-3 3H6a3 3 0 01-3-3V7a3 3 0 013-3h4a3 3 0 013 3v1" />
          </svg>
          Sign Out
        </button>
      </div>
    </aside>
  );
}
