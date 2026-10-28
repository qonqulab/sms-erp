'use client';

import { useEffect } from 'react';

export default function GlobalError({
  error,
  reset,
}: {
  error: Error & { digest?: string };
  reset: () => void;
}) {
  useEffect(() => {
    console.error('Unhandled application error:', error);
  }, [error]);

  return (
    <html lang="en">
      <body>
        <main className="flex min-h-screen items-center justify-center bg-white px-6 text-center text-gray-900">
          <div className="max-w-md">
            <p className="text-sm font-medium uppercase tracking-[0.12em] text-gray-500">Application error</p>
            <h1 className="mt-3 text-3xl font-semibold tracking-tight">Something needs to be retried</h1>
            <p className="mt-3 text-sm leading-6 text-gray-600">
              Your data has not been changed. Please retry the page; if the problem persists, contact your administrator.
            </p>
            <button
              type="button"
              onClick={reset}
              className="mt-7 rounded-lg bg-gray-900 px-4 py-2.5 text-sm font-medium text-white transition-colors hover:bg-gray-800"
            >
              Retry
            </button>
          </div>
        </main>
      </body>
    </html>
  );
}
