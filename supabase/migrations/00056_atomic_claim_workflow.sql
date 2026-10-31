-- ============================================================================
-- 00056: Atomic claim and requisition workflow
-- Claim headers, lines, state transitions, and audit history must be written
-- together. The authenticated database session, not a browser-supplied role,
-- is the authorization boundary.
-- ============================================================================

CREATE OR REPLACE FUNCTION public.rpc_submit_company_request(
  p_user_id uuid,
  p_branch_id uuid,
  p_type text,
  p_payment_preference text,
  p_payment_preference_details text,
  p_note text,
  p_items jsonb
) RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_request_id uuid;
  v_total numeric(15,2);
BEGIN
  IF (SELECT auth.uid()) IS DISTINCT FROM p_user_id THEN
    RAISE EXCEPTION 'Authenticated user does not match request creator' USING ERRCODE = '42501';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM public.profiles
    WHERE id = p_user_id AND is_active
  ) OR NOT (SELECT public.can_access_branch(p_branch_id)) THEN
    RAISE EXCEPTION 'Request creator cannot access this branch' USING ERRCODE = '42501';
  END IF;
  IF p_type NOT IN ('CLAIM', 'REQUISITION')
    OR p_payment_preference NOT IN ('CASH', 'TRANSFER', 'OTHERS') THEN
    RAISE EXCEPTION 'Invalid request type or payment preference';
  END IF;
  IF jsonb_typeof(p_items) IS DISTINCT FROM 'array' OR jsonb_array_length(p_items) = 0 THEN
    RAISE EXCEPTION 'A request must contain at least one item';
  END IF;
  IF EXISTS (
    SELECT 1
    FROM jsonb_to_recordset(p_items) AS item(
      description text, unit text, quantity numeric, price_per_unit numeric, receipt_url text
    )
    WHERE length(trim(COALESCE(item.description, ''))) = 0
      OR item.quantity IS NULL OR item.quantity <= 0
      OR item.price_per_unit IS NULL OR item.price_per_unit < 0
      OR (p_type = 'CLAIM' AND length(trim(COALESCE(item.receipt_url, ''))) = 0)
  ) THEN
    RAISE EXCEPTION 'Each item requires a description, positive quantity, non-negative price, and a receipt for claims';
  END IF;

  INSERT INTO public.company_requests (
    created_by, branch_id, type, status, payment_preference,
    payment_preference_details, total_amount, paid_amount
  ) VALUES (
    p_user_id, p_branch_id, p_type::public.company_request_type, 'SUBMITTED',
    p_payment_preference::public.payment_preference_type,
    NULLIF(trim(COALESCE(p_payment_preference_details, '')), ''), 0, 0
  ) RETURNING id INTO v_request_id;

  INSERT INTO public.company_request_items (
    request_id, description, unit, quantity, price_per_unit, total_price, receipt_url
  )
  SELECT
    v_request_id, trim(item.description), NULLIF(trim(COALESCE(item.unit, '')), ''),
    item.quantity, round(item.price_per_unit, 2), 0,
    NULLIF(trim(COALESCE(item.receipt_url, '')), '')
  FROM jsonb_to_recordset(p_items) AS item(
    description text, unit text, quantity numeric, price_per_unit numeric, receipt_url text
  );

  SELECT total_amount INTO v_total FROM public.company_requests WHERE id = v_request_id;
  INSERT INTO public.company_request_history (request_id, actor_id, action, note)
  VALUES (
    v_request_id, p_user_id, 'CREATED',
    COALESCE(NULLIF(trim(COALESCE(p_note, '')), ''),
      'Requested ' || p_type || ' for ' || COALESCE(v_total, 0)::text)
  );
  RETURN v_request_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.rpc_transition_company_request(
  p_request_id uuid,
  p_user_id uuid,
  p_action text,
  p_note text DEFAULT NULL,
  p_amount numeric DEFAULT NULL,
  p_payment_method text DEFAULT NULL
) RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_request public.company_requests%ROWTYPE;
  v_role text := (SELECT public.get_user_role());
  v_balance numeric(15,2);
  v_status public.company_request_status;
  v_history_action text;
  v_new_paid numeric(15,2);
  v_is_officer boolean := v_role IN ('claim_officer', 'admin', 'owner', 'director');
BEGIN
  IF (SELECT auth.uid()) IS DISTINCT FROM p_user_id THEN
    RAISE EXCEPTION 'Authenticated user does not match workflow actor' USING ERRCODE = '42501';
  END IF;

  SELECT * INTO v_request FROM public.company_requests WHERE id = p_request_id FOR UPDATE;
  IF NOT FOUND OR NOT (SELECT public.can_access_branch(v_request.branch_id)) THEN
    RAISE EXCEPTION 'Company request is unavailable';
  END IF;

  IF p_action = 'APPROVE' THEN
    IF NOT v_is_officer OR v_request.status <> 'SUBMITTED' THEN RAISE EXCEPTION 'Request cannot be approved'; END IF;
    UPDATE public.company_requests SET status = 'APPROVED', approved_by = p_user_id,
      approval_date = now(), approval_note = NULLIF(trim(COALESCE(p_note, '')), '') WHERE id = p_request_id;
    v_history_action := 'APPROVED';
  ELSIF p_action = 'REJECT' THEN
    IF NOT v_is_officer OR v_request.status <> 'SUBMITTED' OR length(trim(COALESCE(p_note, ''))) = 0 THEN
      RAISE EXCEPTION 'A submitted request and rejection reason are required';
    END IF;
    UPDATE public.company_requests SET status = 'REJECTED', reject_reason = trim(p_note) WHERE id = p_request_id;
    v_history_action := 'REJECTED';
  ELSIF p_action = 'DISBURSE' THEN
    IF NOT v_is_officer OR v_request.status NOT IN ('APPROVED', 'PENDING') THEN RAISE EXCEPTION 'Request cannot be disbursed'; END IF;
    v_balance := v_request.total_amount - v_request.paid_amount;
    IF p_amount IS NULL OR p_amount <= 0 OR p_amount > v_balance
      OR p_payment_method NOT IN ('CASH', 'TRANSFER', 'OTHERS') THEN
      RAISE EXCEPTION 'Payment amount or method is invalid';
    END IF;
    IF p_amount < v_balance THEN
      UPDATE public.company_requests SET status = 'PENDING', proposed_amount = round(p_amount, 2),
        payment_method_offered = NULL,
        pending_reason = COALESCE(NULLIF(trim(COALESCE(p_note, '')), ''), 'Waiting to pay remaining ' || (v_balance - p_amount)::text)
      WHERE id = p_request_id;
      v_history_action := 'PARTIAL_PAYMENT_PROPOSED';
    ELSIF p_payment_method::public.payment_preference_type <> v_request.payment_preference THEN
      UPDATE public.company_requests SET status = 'PENDING', paid_amount = v_request.paid_amount + round(p_amount, 2),
        proposed_amount = NULL, payment_method_offered = p_payment_method::public.payment_preference_type,
        pending_reason = NULLIF(trim(COALESCE(p_note, '')), '') WHERE id = p_request_id;
      v_history_action := 'PAYMENT_NEGOTIATION';
    ELSIF p_payment_method = 'CASH' THEN
      UPDATE public.company_requests SET status = 'READY_FOR_CASH', paid_amount = v_request.paid_amount + round(p_amount, 2),
        proposed_amount = NULL, payment_method_offered = NULL, pending_reason = NULL WHERE id = p_request_id;
      v_history_action := 'CASH_READY';
    ELSE
      UPDATE public.company_requests SET status = 'PENDING', paid_amount = v_request.paid_amount + round(p_amount, 2),
        proposed_amount = NULL, payment_method_offered = NULL,
        pending_reason = COALESCE(NULLIF(trim(COALESCE(p_note, '')), ''), 'transfer_pending') WHERE id = p_request_id;
      v_history_action := 'QUEUEING_TRANSFER';
    END IF;
  ELSIF p_action = 'TRANSFER_DONE' THEN
    IF NOT v_is_officer OR v_request.status <> 'PENDING' OR v_request.pending_reason NOT ILIKE '%transfer%' THEN
      RAISE EXCEPTION 'Only a queued transfer can be completed';
    END IF;
    UPDATE public.company_requests SET status = 'COMPLETED', pending_reason = NULL WHERE id = p_request_id;
    v_history_action := 'TRANSFER_COMPLETED';
  ELSIF p_action = 'ACCEPT_PARTIAL' THEN
    IF v_request.created_by <> p_user_id OR COALESCE(v_request.proposed_amount, 0) <= 0 THEN RAISE EXCEPTION 'No partial proposal is available'; END IF;
    v_new_paid := v_request.paid_amount + v_request.proposed_amount;
    UPDATE public.company_requests SET paid_amount = v_new_paid, proposed_amount = NULL, status = 'PENDING',
      pending_reason = 'Waiting to pay remaining ' || (v_request.total_amount - v_new_paid)::text WHERE id = p_request_id;
    v_history_action := 'PARTIAL_PAYMENT_ACCEPTED';
  ELSIF p_action = 'REJECT_PARTIAL' THEN
    IF v_request.created_by <> p_user_id OR length(trim(COALESCE(p_note, ''))) = 0 THEN RAISE EXCEPTION 'A rejection reason is required'; END IF;
    UPDATE public.company_requests SET proposed_amount = NULL, status = 'PENDING',
      pending_reason = 'Employee rejected partial payment: ' || trim(p_note) WHERE id = p_request_id;
    v_history_action := 'PARTIAL_PAYMENT_REJECTED';
  ELSIF p_action = 'COMPLETE' THEN
    IF (v_request.created_by <> p_user_id AND NOT v_is_officer)
      OR NOT (
        v_request.status = 'READY_FOR_CASH'
        OR (v_request.status = 'PENDING' AND v_request.payment_method_offered IS NOT NULL)
      ) THEN
      RAISE EXCEPTION 'Request cannot be completed';
    END IF;
    UPDATE public.company_requests SET status = 'COMPLETED', payment_method_offered = NULL, pending_reason = NULL WHERE id = p_request_id;
    v_history_action := 'CLAIMED';
  ELSIF p_action = 'REJECT_NEGOTIATION' THEN
    IF v_request.created_by <> p_user_id OR v_request.payment_method_offered IS NULL
      OR length(trim(COALESCE(p_note, ''))) = 0 THEN RAISE EXCEPTION 'A negotiated payment method and rejection reason are required'; END IF;
    UPDATE public.company_requests SET status = 'PENDING', pending_reason = 'Employee rejected payment method: ' || trim(p_note) WHERE id = p_request_id;
    v_history_action := 'NEGOTIATION_REJECTED';
  ELSIF p_action = 'FLAG_ISSUE' THEN
    IF NOT v_is_officer OR v_request.status <> 'COMPLETED' OR length(trim(COALESCE(p_note, ''))) = 0 THEN RAISE EXCEPTION 'Only a completed request can be flagged with a note'; END IF;
    UPDATE public.company_requests SET post_claim_issue = trim(p_note) WHERE id = p_request_id;
    v_history_action := 'ISSUE_FLAGGED';
  ELSE
    RAISE EXCEPTION 'Unsupported company-request action';
  END IF;

  INSERT INTO public.company_request_history (request_id, actor_id, action, note)
  VALUES (p_request_id, p_user_id, v_history_action, NULLIF(trim(COALESCE(p_note, '')), ''));
  RETURN p_request_id;
END;
$$;

REVOKE INSERT, UPDATE, DELETE ON public.company_requests FROM authenticated;
REVOKE INSERT, UPDATE, DELETE ON public.company_request_items FROM authenticated;
REVOKE INSERT, UPDATE, DELETE ON public.company_request_history FROM authenticated;
GRANT SELECT ON public.company_requests, public.company_request_items, public.company_request_history TO authenticated;
REVOKE ALL ON FUNCTION public.rpc_submit_company_request(uuid, uuid, text, text, text, text, jsonb) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.rpc_transition_company_request(uuid, uuid, text, text, numeric, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.rpc_submit_company_request(uuid, uuid, text, text, text, text, jsonb) TO authenticated;
GRANT EXECUTE ON FUNCTION public.rpc_transition_company_request(uuid, uuid, text, text, numeric, text) TO authenticated;
