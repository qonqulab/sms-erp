import { supabase } from '@/lib/supabase';
import type { 
  CompanyRequest, 
  CompanyRequestItem, 
  Actor,
  PaymentPreferenceType,
  CompanyRequestType,
  CompanyRequestStatus
} from '@/types/types';

export const claimService = {
  // CREATE Request (Type CLAIM or REQUISITION)
  async createRequest(
    data: {
      type: CompanyRequestType;
      branch_id: string;
      payment_preference: PaymentPreferenceType;
      payment_preference_details?: string;
      items: Omit<CompanyRequestItem, 'id' | 'request_id' | 'created_at'>[];
      note?: string;
    },
    actor: Actor
  ): Promise<string> {
    const { data: requestId, error } = await supabase.rpc('rpc_submit_company_request', {
      p_user_id: actor.id,
      p_branch_id: data.branch_id,
      p_type: data.type,
      p_payment_preference: data.payment_preference,
      p_payment_preference_details: data.payment_preference_details ?? '',
      p_note: data.note ?? '',
      p_items: data.items.map((item) => ({
        description: item.description,
        unit: item.unit ?? '',
        quantity: item.quantity,
        price_per_unit: item.price_per_unit,
        receipt_url: item.receipt_url ?? '',
      })),
    });
    if (error || !requestId) throw new Error(error?.message ?? 'Create request failed');
    return requestId;
  },

  // GET Requests with nested Items and Creator profiles
  async getRequests(filters?: { 
      status?: CompanyRequestStatus | CompanyRequestStatus[]; 
      branch_id?: string;
      created_by?: string;
  }): Promise<CompanyRequest[]> {
    let query = supabase
      .from('company_requests')
      .select(`
        *,
        creator:profiles!company_requests_creator_profile_fkey(name, email, avatar_url, role),
        approver:profiles!company_requests_approver_profile_fkey(name, email, avatar_url, role),
        branch:branches(name),
        items:company_request_items(*),
        history:company_request_history(*, actor:profiles!company_request_history_actor_profile_fkey(name, role, avatar_url))
      `)
      .order('created_at', { ascending: false });

    if (filters?.status) {
      if (Array.isArray(filters.status)) {
        query = query.in('status', filters.status);
      } else {
        query = query.eq('status', filters.status);
      }
    }
    if (filters?.branch_id && filters.branch_id !== 'ALL') query = query.eq('branch_id', filters.branch_id);
    if (filters?.created_by) query = query.eq('created_by', filters.created_by);

    const { data, error } = await query;
    if (error) throw new Error(`Get Requests failed: ${error.message}`);
    return data as CompanyRequest[];
  },

  // APPROVER LOGIC: Approve
  async approveRequest(id: string, note: string | undefined, actor: Actor): Promise<void> {
    await transitionClaim(id, actor, 'APPROVE', note);
  },

  // APPROVER LOGIC: Reject
  async rejectRequest(id: string, reason: string, actor: Actor): Promise<void> {
    await transitionClaim(id, actor, 'REJECT', reason);
  },

  // OFFICER LOGIC: Process disbursement (Partial, Negotiation, Full)
  async processDisbursement(
    id: string,
    currentRequest: CompanyRequest,
    actionData: {
      pay_amount: number;
      payment_method_used: PaymentPreferenceType;
      pending_reason?: string; // mandatory if pay_amount < total OR using different method
    },
    actor: Actor
  ): Promise<void> {
    void currentRequest;
    await transitionClaim(id, actor, 'DISBURSE', actionData.pending_reason, actionData.pay_amount, actionData.payment_method_used);
  },

  // OFFICER LOGIC: Mark Transfer Done
  async markTransferDone(id: string, actor: Actor): Promise<void> {
    await transitionClaim(id, actor, 'TRANSFER_DONE');
  },

  // EMPLOYEE LOGIC: Accept Partial Proposal
  async acceptPartialProposal(id: string, currentRequest: CompanyRequest, actor: Actor): Promise<void> {
    void currentRequest;
    await transitionClaim(id, actor, 'ACCEPT_PARTIAL');
  },

  // EMPLOYEE LOGIC: Reject Partial Proposal
  async rejectPartialProposal(id: string, reason: string, actor: Actor): Promise<void> {
    await transitionClaim(id, actor, 'REJECT_PARTIAL', reason);
  },

  // EMPLOYEE/OFFICER LOGIC: Accept Negotiation or Ready Cash (Complete Claim)
  async completeClaim(id: string, actor: Actor): Promise<void> {
    await transitionClaim(id, actor, 'COMPLETE');
  },

  // EMPLOYEE LOGIC: Reject Negotiation
  async rejectNegotiation(id: string, reason: string, actor: Actor): Promise<void> {
    await transitionClaim(id, actor, 'REJECT_NEGOTIATION', reason);
  },

  // OFFICER LOGIC: Flag Post-Claim Issue
  async flagPostClaimIssue(id: string, issueNote: string, actor: Actor): Promise<void> {
    await transitionClaim(id, actor, 'FLAG_ISSUE', issueNote);
  }
};

async function transitionClaim(
  requestId: string,
  actor: Actor,
  action: string,
  note?: string,
  amount?: number,
  paymentMethod?: PaymentPreferenceType
): Promise<void> {
  const { error } = await supabase.rpc('rpc_transition_company_request', {
    p_request_id: requestId,
    p_user_id: actor.id,
    p_action: action,
    p_note: note ?? null,
    p_amount: amount ?? null,
    p_payment_method: paymentMethod ?? null,
  });
  if (error) throw new Error(error.message);
}
