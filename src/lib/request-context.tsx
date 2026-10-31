'use client';

import { createContext, useContext, useState, useCallback, useMemo } from 'react';
import { useRouter } from 'next/navigation';
import { useAuth } from '@/hooks/useAuth';
import { useBranch } from '@/hooks/useBranch';
import { requireAuthUser } from '@/lib/db/client';
import { requestsDb } from '@/lib/db';
import { supabase } from '@/lib/supabase';
import { notificationService } from '@/lib/services/notification-service';
import { activityLogsDb } from '@/lib/db';
import type { CartItem, DbRequest } from '@/types/types';

type RequestContextType = {
  items: CartItem[];
  add: (id: string, name?: string) => void;
  remove: (id: string) => void;
  updateQty: (id: string, qty: number) => void;
  clear: () => void;
  itemCount: number;
  submit: (args: {
    priority: DbRequest['priority'];
    note?: string;
    promise_date?: string;
    payment_note?: string;
  }) => Promise<DbRequest>;
};

const RequestContext = createContext<RequestContextType | null>(null);

export default function RequestProvider({ children }: { children: React.ReactNode }) {
  const [items, setItems] = useState<CartItem[]>([]);
  const { profile } = useAuth();
  const { activeBranchId } = useBranch();
  const router = useRouter();

  const add = useCallback((id: string, name?: string) => {
    // Block clients from adding to cart if profile is incomplete
    if (profile?.role === 'client' && !profile?.profile_completed) {
      alert('Please complete your profile before adding items to your request.');
      router.push('/dashboard/profile');
      return;
    }
    setItems(prev => {
      const existing = prev.find(item => item.id === id);
      if (existing) {
        return prev.map(item =>
          item.id === id ? { ...item, qty: item.qty + 1 } : item
        );
      }
      return [...prev, { id, qty: 1, name }];
    });
  }, [profile, router]);

  const remove = useCallback((id: string) => {
    setItems(prev => prev.filter(item => item.id !== id));
  }, []);

  const updateQty = useCallback((id: string, qty: number) => {
    if (qty <= 0) {
      setItems(prev => prev.filter(item => item.id !== id));
    } else {
      setItems(prev => prev.map(item =>
        item.id === id ? { ...item, qty } : item
      ));
    }
  }, []);

  const clear = useCallback(() => setItems([]), []);

  const itemCount = useMemo(() => items.reduce((sum, i) => sum + i.qty, 0), [items]);

  const submit = useCallback(async ({
    priority,
    note,
    promise_date,
    payment_note,
  }: {
    priority: DbRequest['priority'];
    note?: string;
    promise_date?: string;
    payment_note?: string;
  }): Promise<DbRequest> => {
    if (items.length === 0) throw new Error('Cart is empty');

    const user = await requireAuthUser();

    const { data: requestId, error } = await supabase.rpc('rpc_submit_client_request', {
      p_user_id: user.id,
      p_branch_id: activeBranchId !== 'ALL' ? activeBranchId : profile?.branch_id ?? null,
      p_priority: priority,
      p_note: note ?? '',
      p_promise_date: promise_date ?? null,
      p_payment_note: payment_note ?? '',
      p_items: items.map((item) => ({ product_id: item.id, quantity: item.qty })),
    });
    if (error || !requestId) throw new Error(error?.message ?? 'Request submission failed');

    const request = await requestsDb.getById(requestId);
    if (!request) throw new Error('Submitted request could not be retrieved');

    // Notify marketing
    await notificationService.notifyRoles(['marketing', 'admin'], {
      title: 'New Order',
      message: `New order submitted by ${user.email ?? 'client'}`,
      type: 'info',
      orderId: request.id,
    });

    // Activity log
    await activityLogsDb.create({
      user_id: user.id,
      user_email: user.email,
      action: 'submit_request',
      entity_type: 'request',
      entity_id: request.id,
      metadata: {
        item_count: items.length,
        total_quantity: itemCount,
        total_price: 0,
        priority,
      },
    });

    clear();
    return request;
  }, [items, itemCount, profile, activeBranchId, clear]);

  const value = useMemo(() => ({
    items, add, remove, updateQty, clear, itemCount, submit,
  }), [items, add, remove, updateQty, clear, itemCount, submit]);

  return (
    <RequestContext.Provider value={value}>
      {children}
    </RequestContext.Provider>
  );
}

export function useRequest() {
  const context = useContext(RequestContext);
  if (!context) throw new Error('useRequest must be used inside RequestProvider');
  return context;
}
