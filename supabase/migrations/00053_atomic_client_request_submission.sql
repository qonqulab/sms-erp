-- ============================================================================
-- 00053: Atomic client order submission
-- A cart submission creates its header, lines, and any required payment
-- promise in one transaction. Prices deliberately remain zero until the
-- marketing pricing RPC snapshots the authoritative price list.
-- ============================================================================

CREATE OR REPLACE FUNCTION public.rpc_submit_client_request(
  p_user_id uuid,
  p_branch_id uuid,
  p_priority text,
  p_note text,
  p_promise_date timestamptz DEFAULT NULL,
  p_payment_note text DEFAULT NULL,
  p_items jsonb DEFAULT '[]'::jsonb
) RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_profile public.profiles%ROWTYPE;
  v_request_id uuid;
  v_branch_id uuid;
BEGIN
  IF (SELECT auth.uid()) IS DISTINCT FROM p_user_id THEN
    RAISE EXCEPTION 'Authenticated user does not match request owner' USING ERRCODE = '42501';
  END IF;

  SELECT * INTO v_profile
  FROM public.profiles
  WHERE id = p_user_id
  FOR UPDATE;

  IF NOT FOUND OR v_profile.role::text <> 'client' OR NOT v_profile.is_active THEN
    RAISE EXCEPTION 'Only active client profiles can submit requests' USING ERRCODE = '42501';
  END IF;
  IF NOT COALESCE(v_profile.profile_completed, false) THEN
    RAISE EXCEPTION 'Complete the client profile before submitting a request';
  END IF;

  v_branch_id := COALESCE(p_branch_id, v_profile.branch_id);
  IF v_branch_id IS NULL OR v_branch_id IS DISTINCT FROM v_profile.branch_id THEN
    RAISE EXCEPTION 'Client requests must use the assigned branch' USING ERRCODE = '42501';
  END IF;
  IF p_priority NOT IN ('normal', 'cito') THEN
    RAISE EXCEPTION 'Unsupported request priority';
  END IF;
  IF jsonb_typeof(p_items) IS DISTINCT FROM 'array' OR jsonb_array_length(p_items) = 0 THEN
    RAISE EXCEPTION 'A request must contain at least one product';
  END IF;
  IF EXISTS (
    SELECT 1
    FROM jsonb_to_recordset(p_items) AS item(product_id uuid, quantity integer)
    LEFT JOIN public.products product ON product.id = item.product_id AND product.is_active = true
    WHERE item.product_id IS NULL OR item.quantity IS NULL OR item.quantity <= 0 OR product.id IS NULL
  ) THEN
    RAISE EXCEPTION 'Each request line requires an active product and positive quantity';
  END IF;
  IF COALESCE(v_profile.debt_amount, 0) > COALESCE(v_profile.debt_limit, 0)
    AND p_promise_date IS NULL THEN
    RAISE EXCEPTION 'A payment promise date is required while the debt limit is exceeded';
  END IF;

  INSERT INTO public.requests (
    user_id, user_email, branch_id, status, priority, total_price, note, created_by, updated_by
  ) VALUES (
    p_user_id, v_profile.email, v_branch_id, 'submitted', p_priority::public.request_priority,
    0, NULLIF(trim(COALESCE(p_note, '')), ''), p_user_id, p_user_id
  ) RETURNING id INTO v_request_id;

  INSERT INTO public.request_items (request_id, product_id, quantity, price_at_order)
  SELECT v_request_id, item.product_id, item.quantity, 0
  FROM jsonb_to_recordset(p_items) AS item(product_id uuid, quantity integer);

  IF COALESCE(v_profile.debt_amount, 0) > COALESCE(v_profile.debt_limit, 0) THEN
    INSERT INTO public.payment_promises (
      user_id, user_email, request_id, promise_date, note
    ) VALUES (
      p_user_id, v_profile.email, v_request_id, p_promise_date,
      NULLIF(trim(COALESCE(p_payment_note, '')), '')
    );
  END IF;

  RETURN v_request_id;
END;
$$;

REVOKE ALL ON FUNCTION public.rpc_submit_client_request(uuid, uuid, text, text, timestamptz, text, jsonb) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.rpc_submit_client_request(uuid, uuid, text, text, timestamptz, text, jsonb) TO authenticated;
