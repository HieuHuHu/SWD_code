// Author: Nguyễn Phồn Hiếu_HE191632 | Date: 9/11/2026
'use client';
import { useEffect } from 'react';
import { useRouter } from 'next/navigation';
import { getSession, homeFor } from '@/lib/api';

export default function Home() {
  const router = useRouter();
  useEffect(() => {
    const s = getSession();
    router.replace(s ? homeFor(s.user.role) : '/services');
  }, [router]);
  return null;
}
