'use client';

import { useState, useEffect } from 'react';
import { cmsService } from '@/lib/services';
import type { CmsSettings } from '@/types/types';

export default function About() {
  const [settings, setSettings] = useState<CmsSettings | null>(null);

  useEffect(() => {
    cmsService.getSettings().then(setSettings).catch(() => null);
  }, []);

  const title = settings?.about_heading || 'Real Experience.\nReal Reliability.';
  const body = settings?.about_text || 'We understand laboratory workflows — not just from theory, but from real operational experience.\n\nOur team brings hands-on knowledge of equipment installation, daily operations, maintenance challenges, and troubleshooting under pressure.';

  return (
    <section id="about" className="py-32 px-4 sm:px-6 lg:px-8">
      <div className="max-w-7xl mx-auto">
        <div className="grid grid-cols-1 lg:grid-cols-2 gap-16 lg:gap-32 items-center">
          <div>
            <h2 className="text-4xl md:text-5xl font-bold mb-6 text-gray-900 whitespace-pre-line">
              {title}
            </h2>
            <p className="text-xl text-gray-600 leading-relaxed max-w-lg whitespace-pre-line">
              {body}
            </p>
          </div>
          <div>
            <div className="rounded-xl border border-gray-200 bg-white p-8 shadow-sm lg:p-12">
              <ul className="space-y-4 text-lg">
                <li className="flex items-start space-x-3">
                  <span className="w-2 h-2 bg-blue-600 rounded-full mt-2 flex-shrink-0" />
                  <span>Equipment selection based on actual throughput needs</span>
                </li>
                <li className="flex items-start space-x-3">
                  <span className="w-2 h-2 bg-blue-600 rounded-full mt-2 flex-shrink-0" />
                  <span>Installation optimized for your lab layout</span>
                </li>
                <li className="flex items-start space-x-3">
                  <span className="w-2 h-2 bg-blue-600 rounded-full mt-2 flex-shrink-0" />
                  <span>24/7 support from technicians who understand your workflow</span>
                </li>
              </ul>
            </div>
          </div>
        </div>
      </div>
    </section>
  );
}
