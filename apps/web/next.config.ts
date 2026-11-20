import type { NextConfig } from "next";

const nextConfig: NextConfig = {
  transpilePackages: ["@aqua/ts-sdk"],
  reactStrictMode: true,
};

export default nextConfig;
