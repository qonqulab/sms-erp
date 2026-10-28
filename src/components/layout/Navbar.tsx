'use client';

import { useState } from 'react';
import Link from 'next/link';
import { useAuth } from '@/hooks/useAuth';
import { useRouter } from 'next/navigation';
import { NotificationBell } from '@/components/ui/NotificationBell';
import BranchIndicator from '@/components/layout/BranchIndicator';

const Navbar = () => {
  const [mobileOpen, setMobileOpen] = useState(false);
  const [profileOpen, setProfileOpen] = useState(false);
  const { profile, logout, loading: authLoading } = useAuth();
  const router = useRouter();

  const handleLogout = async () => {
    await logout();
    window.location.href = '/login';
  };

  return (
    <nav className="fixed inset-x-0 top-0 z-[100] border-b border-gray-200 bg-white">
      <div className="mx-auto max-w-7xl px-4 sm:px-6">
        <div className="flex h-16 items-center lg:h-[4.5rem]">

          {/* LEFT: LOGO */}
          <div className="flex-1 flex items-center">
            <Link href="/" className="text-2xl font-black text-[var(--apple-text-primary)] tracking-tighter">
              ORION
            </Link>
          </div>

          {/* CENTER: MENU TENGAH */}
          <div className="hidden flex-1 items-center justify-center gap-8 md:flex">
            <Link href="/#about" className="text-sm font-medium text-[var(--apple-text-secondary)] transition-colors hover:text-[var(--apple-text-primary)]">
              About
            </Link>
            <Link href="/#products" className="text-sm font-medium text-[var(--apple-text-secondary)] transition-colors hover:text-[var(--apple-text-primary)]">
              Products
            </Link>
            <Link href="/#solutions" className="text-sm font-medium text-[var(--apple-text-secondary)] transition-colors hover:text-[var(--apple-text-primary)]">
              Services
            </Link>
            <Link href="/#contact" className="text-sm font-medium text-[var(--apple-text-secondary)] transition-colors hover:text-[var(--apple-text-primary)]">
              Contact
            </Link>
          </div>

          {/* RIGHT: NOTIFICATION + PROFILE PIC */}
          <div className="flex-1 flex items-center justify-end gap-3">
            {authLoading ? (
              /* Skeleton while auth is resolving */
              <div className="flex items-center gap-3">
                <div className="h-5 w-20 animate-pulse rounded-full bg-gray-200" />
                <div className="h-9 w-9 animate-pulse rounded-full bg-gray-200" />
              </div>
            ) : profile ? (
              <>
                {/* 📍 Multi-Branch Context Switcher / Indicator */}
                <BranchIndicator />

                {/* 🔔 Notification Bell */}
                <NotificationBell />

                {/* Profile Pic & Dropdown */}
                <div className="relative">
                  <button 
                    onClick={() => setProfileOpen(!profileOpen)}
                    className="flex h-9 w-9 items-center justify-center rounded-full bg-[var(--apple-blue)] text-sm font-semibold uppercase text-white transition-colors hover:bg-[var(--apple-blue-hover)]"
                  >
                    {profile.name?.[0] || profile.email?.[0] || '?'}
                  </button>

                  {/* Profile Dropdown */}
                  {profileOpen && (
                    <div className="absolute right-0 z-50 mt-3 w-56 overflow-hidden rounded-xl border border-[var(--apple-border)] bg-white py-2 shadow-lg"
                    >
                      <div className="px-4 py-3 border-b border-[var(--apple-border)] bg-[var(--apple-gray-bg)]/50">
                        <p className="text-sm font-bold text-[var(--apple-text-primary)] truncate">{profile.name || profile.email}</p>
                        <p className="text-[10px] font-black tracking-wider text-[var(--apple-text-tertiary)] uppercase mt-0.5">{profile.role}</p>
                      </div>
                      
                      <div className="py-1">
                        <Link href="/dashboard" onClick={() => setProfileOpen(false)} className="block px-4 py-2.5 text-sm font-bold text-[var(--apple-text-primary)] hover:bg-[var(--apple-gray-bg)] transition-colors">Dashboard</Link>
                        <Link href="/dashboard/settings" onClick={() => setProfileOpen(false)} className="block px-4 py-2 text-sm font-medium text-[var(--apple-text-primary)] hover:bg-[var(--apple-gray-bg)] transition-colors">Settings</Link>
                        <Link href="/dashboard/settings?tab=region" onClick={() => setProfileOpen(false)} className="block px-4 py-2 text-sm font-medium text-[var(--apple-text-primary)] hover:bg-[var(--apple-gray-bg)] transition-colors">Region / Branch</Link>
                        <Link href="/dashboard/settings?tab=language" onClick={() => setProfileOpen(false)} className="block px-4 py-2 text-sm font-medium text-[var(--apple-text-primary)] hover:bg-[var(--apple-gray-bg)] transition-colors">Language</Link>
                        <Link href="/dashboard/notifications" onClick={() => setProfileOpen(false)} className="block px-4 py-2 text-sm font-medium text-[var(--apple-text-primary)] hover:bg-[var(--apple-gray-bg)] transition-colors">Notifications</Link>
                        <Link href="/help" onClick={() => setProfileOpen(false)} className="block px-4 py-2 text-sm font-medium text-[var(--apple-text-primary)] hover:bg-[var(--apple-gray-bg)] transition-colors">Help</Link>
                      </div>
                      
                      <div className="border-t border-[var(--apple-border)] py-1 mt-1">
                        <button
                          onClick={() => { setProfileOpen(false); handleLogout(); }}
                          className="w-full text-left px-4 py-2.5 text-sm font-bold text-[var(--apple-danger)] hover:bg-red-50 transition-colors"
                        >
                          Sign Out
                        </button>
                      </div>
                    </div>
                  )}
                </div>
              </>
            ) : (
              <Link
                href="/login"
                className="rounded-lg bg-blue-600 px-4 py-2 text-sm font-medium text-white transition-colors hover:bg-blue-700"
              >
                Get Started
              </Link>
            )}

            {/* Mobile menu btn */}
            <button
              onClick={() => setMobileOpen((prev) => !prev)}
              className="ml-1 rounded-lg bg-[var(--apple-gray-bg)] px-3 py-2 text-xs font-medium text-[var(--apple-text-primary)] md:hidden"
            >
              {mobileOpen ? 'Close' : 'Menu'}
            </button>
          </div>

        </div>
      </div>

      {/* MOBILE MENU */}
      {mobileOpen && (
          <div className="overflow-hidden border-t border-[var(--apple-border)] bg-white md:hidden"
          >
            <div className="px-6 py-6 space-y-4">
              <Link href="/#about" onClick={() => setMobileOpen(false)} className="block text-lg font-medium text-[var(--apple-text-primary)]">About</Link>
              <Link href="/#products" onClick={() => setMobileOpen(false)} className="block text-lg font-medium text-[var(--apple-text-primary)]">Products</Link>
              <Link href="/#solutions" onClick={() => setMobileOpen(false)} className="block text-lg font-medium text-[var(--apple-text-primary)]">Services</Link>
              <Link href="/#contact" onClick={() => setMobileOpen(false)} className="block text-lg font-medium text-[var(--apple-text-primary)]">Contact</Link>
              
              {profile && (
                <div className="pt-6 border-t border-[var(--apple-border)] mt-4">
                  <Link href="/dashboard" onClick={() => setMobileOpen(false)} className="block text-[var(--apple-blue)] font-black text-lg">
                    Go to Dashboard →
                  </Link>
                </div>
              )}
            </div>
          </div>
      )}
    </nav>
  );
};

export default Navbar;
