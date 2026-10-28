'use client';

import Link from 'next/link';
import { useState, useEffect } from 'react';
import { cmsService } from '@/lib/services';
import type { CmsSettings } from '@/types/types';

export default function Hero() {
  const [settings, setSettings] = useState<CmsSettings | null>(null);

  useEffect(() => {
    cmsService.getSettings().then(setSettings).catch(() => null);
  }, []);

  const title = settings?.hero_title || 'Precision Laboratory Systems\nBuilt for Real Operations';
  const subtitle = settings?.hero_subtitle || 'Equipment, reagents, and technical support for laboratories across Indonesia.';
  // Files in Next.js' public directory are served from the site root.
  // Keep the local asset as a reliable fallback when CMS has no video URL.
  const videoUrl = settings?.hero_video_url?.trim() || '/videos/hero.mp4';
  const ctaText = 'Explore Products';
  const ctaLink = '/dashboard/client/products';

  return (
    <section className="relative min-h-[42rem] w-full overflow-hidden sm:min-h-screen">
      {videoUrl ? (
        <video
          className="absolute inset-0 w-full h-full object-cover"
          autoPlay
          muted
          loop
          playsInline
        >
          <source src={videoUrl} type="video/mp4" />
        </video>
      ) : (
        <div className="absolute inset-0 w-full h-full bg-slate-900" />
      )}

      <div className="absolute inset-0 bg-black/60" />

      <div className="relative z-20 flex min-h-[42rem] flex-col items-center justify-center px-5 text-center sm:min-h-screen sm:px-6">
        <h1
          className="max-w-4xl whitespace-pre-line text-4xl font-semibold leading-[1.05] tracking-tight text-white sm:text-5xl lg:text-6xl"
          style={{ color: '#ffffff' }}
        >
          {title}
        </h1>

        <p
          className="mt-6 max-w-xl text-base leading-relaxed text-white sm:text-lg"
          style={{ color: '#ffffff' }}
        >
          {subtitle}
        </p>

        <div
          className="mt-10 flex w-full flex-col gap-3 sm:w-auto sm:flex-row sm:gap-4"
        >
          <Link
            href={ctaLink}
            className="rounded-lg bg-blue-600 px-6 py-3 text-sm font-medium text-white transition-colors duration-150 hover:bg-blue-700"
          >
            {ctaText}
          </Link>

          <Link
            href="#contact"
            className="rounded-lg bg-white px-6 py-3 text-sm font-medium text-gray-900 transition-colors hover:bg-gray-100"
          >
            Contact Us
          </Link>
        </div>
      </div>
    </section>
  );
}
