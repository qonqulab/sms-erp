import type { NextConfig } from "next";

const nextConfig: NextConfig = {
  reactCompiler: true,
  async redirects() {
    return [
      { source: '/about', destination: '/', permanent: false },
      { source: '/services', destination: '/', permanent: false },
      { source: '/contact', destination: '/', permanent: false },
      { source: '/dashboard/admin', destination: '/dashboard/admin-panel', permanent: false },
      { source: '/dashboard/admin/:path*', destination: '/dashboard/admin-panel/:path*', permanent: false },
      { source: '/dashboard/technician/inventory', destination: '/dashboard/delivery/inventory', permanent: false },
    ];
  },
};

export default nextConfig;
