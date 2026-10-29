import type { Metadata } from "next";
import "./globals.css";

export const metadata: Metadata = {
  title: "app",
  description: "ai-dev-template から作ったアプリ",
};

export default function RootLayout({
  children,
}: Readonly<{ children: React.ReactNode }>) {
  return (
    <html lang="ja">
      <body>{children}</body>
    </html>
  );
}
