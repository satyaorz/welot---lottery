import type { Metadata } from "next";
import { Bangers, Press_Start_2P, Space_Grotesk } from "next/font/google";
import "./globals.css";

const fontDisplay = Bangers({
  variable: "--font-display",
  subsets: ["latin"],
  weight: "400",
});

const fontBody = Space_Grotesk({
  variable: "--font-body",
  subsets: ["latin"],
  weight: ["400", "500", "600", "700"],
});

const fontPixel = Press_Start_2P({
  variable: "--font-pixel",
  subsets: ["latin"],
  weight: "400",
});

export const metadata: Metadata = {
  title: "welot-lottery",
  description: "No-loss savings lottery UI.",
};

export default function RootLayout({
  children,
}: Readonly<{
  children: React.ReactNode;
}>) {
  return (
    <html lang="en">
      <body
        className={`${fontBody.variable} ${fontDisplay.variable} ${fontPixel.variable} antialiased`}
      >
        {children}
      </body>
    </html>
  );
}
