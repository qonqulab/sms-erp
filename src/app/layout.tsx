import type { Metadata } from 'next';
import './globals.css';
import './layout.css';
import RequestProvider from '@/lib/request-context';
import { AuthProvider } from '@/hooks/useAuth';
import AnnouncementBanner from '@/components/layout/AnnouncementBanner';

export const metadata: Metadata = {
  title: 'SMS Laboratory Systems - Precision Support for Indonesian Laboratories',
  description:
    'Supplying, supporting, and sustaining laboratory equipment across Indonesia. Hematology, Chemistry, POCT systems with 24/7 service.',
};

import { BranchProvider } from '@/hooks/useBranch';

export default function RootLayout({
  children,
}: {
  children: React.ReactNode;
}) {
  return (
    <html lang="en" className="scroll-smooth" data-scroll-behavior="smooth">
      <body className="antialiased bg-white text-gray-900">
      <AuthProvider>
        <BranchProvider>
          <AnnouncementBanner />
          <RequestProvider>
            {children}
          </RequestProvider>
        </BranchProvider>
      </AuthProvider>
      </body>
    </html>
  );
}
