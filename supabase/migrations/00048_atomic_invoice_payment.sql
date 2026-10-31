-- ============================================================================
-- 00048: Atomic invoice settlement
-- Keep invoice state and the financial ledger in one transaction so a browser
-- retry or an insertion failure can never leave accounting out of balance.
-- ============================================================================

CREATE OR REPLACE FUNCTION public.rpc_mark_invoice_paid(
  p_invoice_id uuid,
  p_user_id uuid,
  p_payment_method text,
  p_payment_ref text
) RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_invoice public.invoices%ROWTYPE;
BEGIN
  IF (SELECT auth.uid()) IS DISTINCT FROM p_user_id
    OR (SELECT public.get_user_role()) NOT IN ('finance', 'admin', 'owner') THEN
    RAISE EXCEPTION 'Unauthorized invoice payment';
  END IF;

  SELECT * INTO v_invoice
  FROM public.invoices
  WHERE id = p_invoice_id
  FOR UPDATE;

  IF NOT FOUND OR NOT (SELECT public.can_access_branch(v_invoice.branch_id)) THEN
    RAISE EXCEPTION 'Invoice is unavailable for payment';
  END IF;
  IF v_invoice.status IN ('cancelled', 'credited') THEN
    RAISE EXCEPTION 'Cancelled or credited invoices cannot be paid';
  END IF;

  UPDATE public.invoices
  SET status = 'paid',
      paid_at = COALESCE(paid_at, now()),
      payment_method = p_payment_method,
      payment_ref = p_payment_ref,
      updated_by = p_user_id,
      updated_at = now()
  WHERE id = p_invoice_id;

  INSERT INTO public.financial_transactions (
    branch_id, transaction_type, direction, amount, reference_id,
    reference_table, description, payment_method, payment_ref, recorded_by
  ) VALUES (
    v_invoice.branch_id, 'invoice_payment', 'inflow', v_invoice.total,
    p_invoice_id, 'invoices',
    'Payment for invoice ' || v_invoice.invoice_number,
    p_payment_method, p_payment_ref, p_user_id
  )
  ON CONFLICT (reference_table, reference_id)
    WHERE reference_table = 'invoices' AND transaction_type = 'invoice_payment'
    DO NOTHING;

  RETURN p_invoice_id;
END;
$$;

REVOKE ALL ON FUNCTION public.rpc_mark_invoice_paid(uuid, uuid, text, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.rpc_mark_invoice_paid(uuid, uuid, text, text) TO authenticated;
