// Author: Nguyễn Phồn Hiếu_HE191632 | Date: 9/11/2026
import type { Metadata } from 'next';
import './globals.css';

export const metadata: Metadata = {
  title: 'AutoCare – Đặt lịch dịch vụ',
  description: 'AutoCare – Đăng ký, đăng nhập, xe của tôi và đặt lịch dịch vụ (UC01, UC02, UC05, UC10, UC13)',
};

export default function RootLayout({ children }: { children: React.ReactNode }) {
  return (
    <html lang="vi">
      <body>{children}</body>
    </html>
  );
}
