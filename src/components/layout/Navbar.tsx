'use client';

import { useEffect, useState } from 'react';
import Link from 'next/link';
import { useAuth } from '@/hooks/useAuth';
import { useRouter } from 'next/navigation';
import { NotificationBell } from '@/components/ui/NotificationBell';
import BranchIndicator from '@/components/layout/BranchIndicator';

const Navbar = () => {
  const [mobileOpen, setMobileOpen] = useState(false);
  const [profileOpen, setProfileOpen] = useState(false);
  const [hasScrolled, setHasScrolled] = useState(false);
  const { profile, logout, loading: authLoading } = useAuth();
  const router = useRouter();

  useEffect(() => {
    const updateScrollState = () => setHasScrolled(window.scrollY > 24);
    updateScrollState();
    window.addEventListener('scroll', updateScrollState, { passive: true });
    return () => window.removeEventListener('scroll', updateScrollState);
  }, []);

  const handleLogout = async () => {
    await logout();
    router.push('/login');
  };

  const useSolidSurface = hasScrolled || mobileOpen;
  const surfaceClass = useSolidSurface
    ? 'border-gray-200 bg-white shadow-sm'
    : 'border-transparent bg-transparent';
  const foregroundClass = useSolidSurface
    ? 'text-[var(--apple-text-primary)]'
    : 'text-white';
  const mutedForegroundClass = useSolidSurface
    ? 'text-[var(--apple-text-secondary)] hover:text-[var(--apple-text-primary)]'
    : 'text-white hover:text-white';

  return (
    <nav className={`fixed inset-x-0 top-0 z-[100] border-b transition-[background-color,border-color,box-shadow] duration-300 ease-out ${surfaceClass}`}>
      <div className="mx-auto max-w-7xl px-4 sm:px-6">
        <div className="flex h-16 items-center lg:h-[4.5rem]">

          {/* LEFT: LOGO */}
          <div className="flex-1 flex items-center">
            <Link href="/" className={`text-2xl font-black tracking-tighter transition-colors duration-300 ${foregroundClass}`}>
              ORION
            </Link>
          </div>

          {/* CENTER: MENU TENGAH */}
          <div className="hidden flex-1 items-center justify-center gap-8 md:flex">
            <Link href="/#about" className={`text-sm font-medium transition-colors duration-300 ${mutedForegroundClass}`}>
              About
            </Link>
            <Link href="/#products" className={`text-sm font-medium transition-colors duration-300 ${mutedForegroundClass}`}>
              Products
            </Link>
            <Link href="/#solutions" className={`text-sm font-medium transition-colors duration-300 ${mutedForegroundClass}`}>
              Services
            </Link>
            <Link href="/#contact" className={`text-sm font-medium transition-colors duration-300 ${mutedForegroundClass}`}>
              Contact
            </Link>
          </div>

          {/* RIGHT: NOTIFICATION + PROFILE PIC */}
          <div className="flex-1 flex items-center justify-end gap-3">
            {authLoading ? (
              /* Skeleton while auth is resolving */
              <div className="flex items-center gap-3">
                <div className={`h-5 w-20 rounded-full ${useSolidSurface ? 'bg-gray-200' : 'bg-white/70'}`} />
                <div className={`h-9 w-9 rounded-full ${useSolidSurface ? 'bg-gray-200' : 'bg-white/70'}`} />
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
                className={`rounded-lg px-4 py-2 text-sm font-medium transition-colors duration-200 ${useSolidSurface ? 'bg-blue-600 text-white hover:bg-blue-700' : 'bg-white text-gray-900 hover:bg-gray-100'}`}
              >
                Get Started
              </Link>
            )}

            {/* Mobile menu btn */}
            <button
              onClick={() => setMobileOpen((prev) => !prev)}
              className={`ml-1 rounded-lg border px-3 py-2 text-xs font-medium transition-colors duration-300 md:hidden ${useSolidSurface ? 'border-gray-200 bg-gray-50 text-[var(--apple-text-primary)] hover:bg-gray-100' : 'border-white/70 bg-transparent text-white hover:border-white'}`}
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
