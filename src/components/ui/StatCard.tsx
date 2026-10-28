'use client';

interface StatCardProps {
  label: string;
  value: string | number;
  sub?: string;
  color?: 'blue' | 'green' | 'yellow' | 'red' | 'purple' | 'gray';
  /** Retained for compatible callers; metric cards intentionally use no decoration. */
  icon?: React.ReactNode;
}

const COLOR_MAP = {
  blue: 'from-blue-500 to-blue-600',
  green: 'from-emerald-500 to-emerald-600',
  yellow: 'from-amber-500 to-amber-600',
  red: 'from-red-500 to-red-600',
  purple: 'from-purple-500 to-purple-600',
  gray: 'from-gray-500 to-gray-600',
};

export function StatCard({ label, value, sub, color = 'blue' }: StatCardProps) {
  return (
    <div className="relative overflow-hidden rounded-2xl border border-gray-100 bg-white p-5 transition-shadow hover:shadow-md dark:border-gray-800 dark:bg-gray-900">
      <div className={`absolute -right-4 -top-4 h-20 w-20 rounded-full bg-gradient-to-br ${COLOR_MAP[color]} opacity-10`} />
      <div className="relative">
        <div>
          <p className="text-xs font-medium uppercase tracking-wider text-gray-500 dark:text-gray-400">
            {label}
          </p>
          <p className="mt-1 text-2xl font-bold text-gray-900 dark:text-white">
            {value}
          </p>
          {sub && (
            <p className="mt-0.5 text-xs text-gray-500 dark:text-gray-400">{sub}</p>
          )}
        </div>
      </div>
    </div>
  );
}
