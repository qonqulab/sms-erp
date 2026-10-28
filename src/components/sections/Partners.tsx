'use client';

import { useState, useEffect } from 'react';
import { cmsService } from '@/lib/services';
import type { CmsPartner } from '@/types/types';

export default function Partners() {
  const [cmsPartners, setCmsPartners] = useState<CmsPartner[]>([]);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    cmsService.getPartners().then(setCmsPartners).finally(() => setLoading(false));
  }, []);

  const displayPartners = cmsPartners.sort((a,b) => (a.sort_order || 0) - (b.sort_order || 0)).map((p) => ({ name: p.name, logo: p.logo_url, website: p.website_url }));

  return (
    <section className="py-24 px-4 sm:px-6 lg:px-8 bg-gray-50">
      <div className="max-w-7xl mx-auto">
        <div className="mb-16 text-center">
          <h3 className="text-2xl font-bold text-gray-900 mb-2">Trusted Partners</h3>
          <p className="text-gray-600">Working with leading laboratory equipment manufacturers</p>
        </div>

        {loading ? (
          <div className="grid grid-cols-2 md:grid-cols-3 lg:grid-cols-6 gap-8 items-center justify-items-center">
            {[1, 2, 3, 4, 5, 6].map((i) => (
              <div key={i} className="h-20 w-32 bg-white rounded-2xl animate-pulse" />
            ))}
          </div>
        ) : (
          <div className="grid grid-cols-2 md:grid-cols-3 lg:grid-cols-6 gap-8 lg:gap-12 items-center justify-items-center">
            {displayPartners.map((partner) => (
              <div
                key={partner.name}
                className="relative flex h-20 w-32 items-center justify-center overflow-hidden rounded-xl border border-gray-200 bg-white p-4 shadow-sm transition-colors hover:border-gray-300"
              >
                {partner.logo?.startsWith('/') || partner.logo?.startsWith('http') ? (
                  <img src={partner.logo} alt={partner.name} className="max-h-full max-w-full object-contain" />
                ) : (
                  <div className="text-sm font-semibold text-gray-500">
                    {partner.name}
                  </div>
                )}
              </div>
            ))}
          </div>
        )}
      </div>
    </section>
  );
}
