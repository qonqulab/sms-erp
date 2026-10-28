import Link from 'next/link';

export default function NotFound() {
  return (
    <main className="flex min-h-screen items-center justify-center bg-white px-6 text-center">
      <div className="max-w-md">
        <p className="text-sm font-medium uppercase tracking-[0.12em] text-gray-500">404</p>
        <h1 className="mt-3 text-3xl font-semibold tracking-tight text-gray-900">Page not found</h1>
        <p className="mt-3 text-sm leading-6 text-gray-600">
          The address may be outdated, or this page may no longer be available.
        </p>
        <Link
          href="/"
          className="mt-7 inline-flex rounded-lg bg-gray-900 px-4 py-2.5 text-sm font-medium text-white transition-colors hover:bg-gray-800"
        >
          Return home
        </Link>
      </div>
    </main>
  );
}
