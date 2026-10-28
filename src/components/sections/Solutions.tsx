'use client';

import Link from 'next/link';
import Image from 'next/image';
import { useState, useEffect } from 'react';
import { cmsService } from '@/lib/services';
import type { CmsSolution } from '@/types/types';

export default function Solutions() {
  const [loading, setLoading] = useState(true);
  const [solutions, setSolutions] = useState<CmsSolution[]>([]);

  useEffect(() => {
    cmsService.getSolutions().then(setSolutions).finally(() => setLoading(false));
  }, []);

  const title = 'Complete Laboratory Solutions';
  const subtitle = 'From equipment to consumables to full-service support — everything your lab needs to operate reliably.';

  return (
    <section id="solutions" className="bg-white px-4 py-24 sm:px-6 lg:px-8">
      <div className="max-w-7xl mx-auto">
        <div className="mb-24 text-center">
          <h2 className="text-4xl md:text-5xl font-bold mb-6 text-gray-900">
            {title}
          </h2>
          <p className="text-xl text-gray-600 max-w-2xl mx-auto">
            {subtitle}
          </p>
        </div>

        {loading ? (
          <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-8">
            {[1, 2, 3].map((i) => (
              <div key={i} className="bg-white rounded-3xl h-96 animate-pulse" />
            ))}
          </div>
        ) : solutions.length === 0 ? (
          <div className="text-center py-12 text-gray-500 bg-white rounded-3xl border border-dashed border-gray-200">
            No solutions currently available.
          </div>
        ) : (
          <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-8">
            {solutions.map((solution) => (
              <div
                key={solution.slug || solution.id}
                className="group overflow-hidden rounded-xl border border-gray-200 bg-white shadow-sm transition-colors hover:border-gray-300"
              >
                <div className="h-48 lg:h-56 overflow-hidden bg-gray-100 relative">
                  <Image
                    src={solution.image_url || ''}
                    alt={solution.title}
                    fill
                    className="object-cover"
                    sizes="(max-width: 768px) 100vw, (max-width: 1200px) 50vw, 33vw"
                  />
                </div>
                <div className="p-8">
                  <span className="mb-4 inline-block text-sm font-medium text-gray-500">
                    {solution.category}
                  </span>
                  <h3 className="mb-3 text-2xl font-bold text-gray-900">
                    {solution.title}
                  </h3>
                  <p className="text-gray-600 mb-6 leading-relaxed">
                    {solution.description}
                  </p>
                  <Link
                    href={`/solution/${solution.slug}`}
                    className="flex text-lg font-medium text-blue-600 transition-colors hover:text-blue-700"
                  >
                    Learn More →
                  </Link>
                </div>
              </div>
            ))}
          </div>
        )}
      </div>
    </section>
  );
}
