-- ============================================================================
-- 00051: Atomic purchase-request workflow
-- Header, lines, derived total, and approval decision are business data. They
-- must not be assembled from independent browser mutations.
-- ============================================================================

ALTER TABLE public.purchase_request_items
  DROP CONSTRAINT IF EXISTS purchase_request_items_estimated_price_nonnegative;
ALTER TABLE public.purchase_request_items
  ADD CONSTRAINT purchase_request_items_estimated_price_nonnegative
  CHECK (estimated_price >= 0);

CREATE INDEX IF NOT EXISTS idx_purchase_request_items_request
  ON public.purchase_request_items (purchase_request_id);

CREATE OR REPLACE FUNCTION public.rpc_submit_purchase_request(
  p_branch_id uuid,
  p_user_id uuid,
  p_title text,
  p_notes text,
  p_items jsonb
) RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_request_id uuid;
  v_total numeric(15,2);
  v_role text := (SELECT public.get_user_role());
BEGIN
  IF (SELECT auth.uid()) IS DISTINCT FROM p_user_id
    OR NOT (
      v_role IN ('warehouse', 'purchasing', 'admin', 'owner')
      OR (SELECT public.has_feature('CREATE_PR'))
    ) THEN
    RAISE EXCEPTION 'Unauthorized purchase-request submission' USING ERRCODE = '42501';
  END IF;

  IF p_branch_id IS NULL OR NOT (SELECT public.can_access_branch(p_branch_id)) THEN
    RAISE EXCEPTION 'Purchase-request branch is unavailable' USING ERRCODE = '42501';
  END IF;
  IF length(trim(COALESCE(p_title, ''))) = 0 THEN
    RAISE EXCEPTION 'Purchase-request title is required';
  END IF;
  IF jsonb_typeof(p_items) IS DISTINCT FROM 'array' OR jsonb_array_length(p_items) = 0 THEN
    RAISE EXCEPTION 'A purchase request must contain at least one item';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM jsonb_to_recordset(p_items) AS item(
      product_id uuid,
      item_name text,
      quantity integer,
      unit text,
      estimated_price numeric
    )
    WHERE length(trim(COALESCE(item_name, ''))) = 0
      OR item.quantity IS NULL OR item.quantity <= 0
      OR length(trim(COALESCE(item.unit, ''))) = 0
      OR item.estimated_price IS NULL OR item.estimated_price < 0
  ) THEN
    RAISE EXCEPTION 'Every purchase-request item requires a name, positive quantity, unit, and non-negative estimate';
  END IF;

  INSERT INTO public.purchase_requests (
    branch_id, requested_by, status, title, notes, total_estimated
  ) VALUES (
    p_branch_id, p_user_id, 'submitted', trim(p_title), NULLIF(trim(COALESCE(p_notes, '')), ''), 0
  ) RETURNING id INTO v_request_id;

  INSERT INTO public.purchase_request_items (
    purchase_request_id, product_id, item_name, quantity, unit, estimated_price
  )
  SELECT
    v_request_id,
    item.product_id,
    trim(item.item_name),
    item.quantity,
    trim(item.unit),
    round(item.estimated_price, 2)
  FROM jsonb_to_recordset(p_items) AS item(
    product_id uuid,
    item_name text,
    quantity integer,
    unit text,
    estimated_price numeric
  );

  SELECT COALESCE(round(sum(quantity * estimated_price), 2), 0)
    INTO v_total
    FROM public.purchase_request_items
    WHERE purchase_request_id = v_request_id;

  UPDATE public.purchase_requests
  SET total_estimated = v_total,
      updated_at = now()
  WHERE id = v_request_id;

  RETURN v_request_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.rpc_decide_purchase_request(
  p_purchase_request_id uuid,
  p_user_id uuid,
  p_decision text,
  p_rejection_reason text DEFAULT NULL
) RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_request public.purchase_requests%ROWTYPE;
  v_role text := (SELECT public.get_user_role());
BEGIN
  IF (SELECT auth.uid()) IS DISTINCT FROM p_user_id
    OR NOT (
      v_role IN ('boss', 'director', 'admin', 'owner')
      OR (SELECT public.has_feature('PR_APPROVALS'))
    ) THEN
    RAISE EXCEPTION 'Unauthorized purchase-request decision' USING ERRCODE = '42501';
  END IF;
  IF p_decision NOT IN ('approved', 'rejected') THEN
    RAISE EXCEPTION 'Purchase-request decision must be approved or rejected';
  END IF;
  IF p_decision = 'rejected' AND length(trim(COALESCE(p_rejection_reason, ''))) = 0 THEN
    RAISE EXCEPTION 'A rejection reason is required';
  END IF;

  SELECT * INTO v_request
  FROM public.purchase_requests
  WHERE id = p_purchase_request_id
  FOR UPDATE;

  IF NOT FOUND OR NOT (SELECT public.can_access_branch(v_request.branch_id)) THEN
    RAISE EXCEPTION 'Purchase request is unavailable';
  END IF;
  IF v_request.status <> 'submitted' THEN
    RAISE EXCEPTION 'Only submitted purchase requests can be decided';
  END IF;

  UPDATE public.purchase_requests
  SET status = p_decision::public.purchase_request_status,
      approved_by = CASE WHEN p_decision = 'approved' THEN p_user_id ELSE NULL END,
      approved_at = CASE WHEN p_decision = 'approved' THEN now() ELSE NULL END,
      rejection_reason = CASE
        WHEN p_decision = 'rejected' THEN trim(p_rejection_reason)
        ELSE NULL
      END,
      updated_at = now()
  WHERE id = p_purchase_request_id;

  RETURN p_purchase_request_id;
END;
$$;

ALTER TABLE public.purchase_requests ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.purchase_request_items ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS purchase_requests_read ON public.purchase_requests;
CREATE POLICY purchase_requests_read ON public.purchase_requests
  FOR SELECT TO authenticated
  USING (
    requested_by = (SELECT auth.uid())
    OR (
      (SELECT public.get_user_role()) <> 'client'
      AND (SELECT public.can_access_branch(branch_id))
    )
  );

DROP POLICY IF EXISTS purchase_request_items_read ON public.purchase_request_items;
CREATE POLICY purchase_request_items_read ON public.purchase_request_items
  FOR SELECT TO authenticated
  USING (
    EXISTS (
      SELECT 1
      FROM public.purchase_requests request
      WHERE request.id = purchase_request_id
        AND (
          request.requested_by = (SELECT auth.uid())
          OR (
            (SELECT public.get_user_role()) <> 'client'
            AND (SELECT public.can_access_branch(request.branch_id))
          )
        )
    )
  );

GRANT SELECT ON public.purchase_requests, public.purchase_request_items TO authenticated;
GRANT EXECUTE ON FUNCTION public.rpc_submit_purchase_request(uuid, uuid, text, text, jsonb) TO authenticated;
GRANT EXECUTE ON FUNCTION public.rpc_decide_purchase_request(uuid, uuid, text, text) TO authenticated;
REVOKE ALL ON FUNCTION public.rpc_submit_purchase_request(uuid, uuid, text, text, jsonb) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.rpc_decide_purchase_request(uuid, uuid, text, text) FROM PUBLIC;
