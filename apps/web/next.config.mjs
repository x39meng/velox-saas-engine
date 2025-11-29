/** @type {import('next').NextConfig} */
const nextConfig = {
  output: "standalone",
  reactStrictMode: true,
  transpilePackages: ["@repo/ui", "@repo/core", "@repo/config", "@repo/database"],
  experimental: {
    serverActions: {
      allowedOrigins: ["app.com", "localhost:3000"]
    }
  }
};

export default nextConfig;
