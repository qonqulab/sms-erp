// ============================================================================
// AUTO-APPROVE SERVICE — Automated boss approval based on client debt limits
// ============================================================================

import { supabase } from '@/lib/db/client';
import type { DbRequest } from '@/types/types';

export interface AutoApproveSettings {
  auto_approve_enabled: boolean;
  auto_approve_min_spend: number;
  auto_approve_default_limit: number;
}

export interface AutoApproveResult {
  approved: DbRequest[];
  rejected: DbRequest[];
  skipped: { request: DbRequest; reason: string }[];
}

export const autoApproveService = {
  /**
   * Fetch auto-approve settings for a branch
   */
  async getSettings(branchId: string): Promise<AutoApproveSettings> {
    const { data, error } = await supabase
      .from('branches')
      .select('auto_approve_enabled, auto_approve_min_spend, auto_approve_default_limit')
      .eq('id', branchId)
      .single();

    if (error || !data) {
      return {
        auto_approve_enabled: false,
        auto_approve_min_spend: 5000000,
        auto_approve_default_limit: 500000,
      };
    }

    return {
      auto_approve_enabled: data.auto_approve_enabled ?? false,
      auto_approve_min_spend: data.auto_approve_min_spend ?? 5000000,
      auto_approve_default_limit: data.auto_approve_default_limit ?? 500000,
    };
  },

  /**
   * Save auto-approve settings for a branch
   */
  async updateSettings(branchId: string, settings: Partial<AutoApproveSettings>): Promise<void> {
    const { error } = await supabase
      .from('branches')
      .update(settings)
      .eq('id', branchId);

    if (error) throw new Error(error.message);
  },

  /**
   * Calculate total lifetime spend for a client (completed/resolved orders)
   */
  async getClientTotalSpent(userId: string): Promise<number> {
    const { data, error } = await supabase
      .from('requests')
      .select('total_price')
      .eq('user_id', userId)
      .in('status', ['completed', 'resolved']);

    if (error || !data) return 0;
    return data.reduce((sum, r) => sum + (r.total_price || 0), 0);
  },



  /**
   * Process a single request automatically (used in background side-effects)
   */
  async processSingleRequest(
    request: DbRequest,
    actor: { id: string; email: string }
  ): Promise<void> {
    // This decision used to impersonate a boss in the browser. The database
    // now evaluates all inputs atomically and authorizes the actual actor.
    const { error } = await supabase.rpc('rpc_auto_approve_priced_request', {
      p_order_id: request.id,
      p_user_id: actor.id,
    });
    if (error) throw new Error(error.message);
  },
};
