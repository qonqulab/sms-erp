-- ============================================================================
-- 00047: Workflow authorization hardening
-- The UI is not an authorization boundary. Enforce the same request state
-- machine in Postgres so a user cannot bypass it by calling the REST API.
-- ============================================================================

CREATE OR REPLACE FUNCTION public.has_feature(p_feature text)
RETURNS boolean
LANGUAGE sql
SECURITY DEFINER
STABLE
SET search_path = public
AS $$
  SELECT COALESCE(p_feature = ANY(features), false)
  FROM public.profiles
  WHERE id = (SELECT auth.uid());
$$;

REVOKE ALL ON FUNCTION public.has_feature(text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.has_feature(text) TO authenticated;

-- A delivery grant must be honored by every operational table, not just the
-- page route. The actor must still be the log owner; this does not turn a
-- grant into permission to edit someone else's shipment.
DROP POLICY IF EXISTS delivery_logs_insert ON public.delivery_logs;
CREATE POLICY delivery_logs_feature_insert ON public.delivery_logs
  FOR INSERT TO authenticated
  WITH CHECK (
    (technician_id = (SELECT auth.uid()) AND (
      (SELECT public.get_user_role()) = 'technician'
      OR (SELECT public.has_feature('DELIVERY'))
      OR (SELECT public.has_feature('MY_INVENTORY'))
    ))
    OR
    (courier_id = (SELECT auth.uid()) AND (
      (SELECT public.get_user_role()) = 'courier'
      OR (SELECT public.has_feature('COURIER'))
    ))
  );

DROP POLICY IF EXISTS delivery_proofs_read ON storage.objects;
CREATE POLICY delivery_proofs_feature_read ON storage.objects
  FOR SELECT TO authenticated
  USING (
    bucket_id = 'delivery-proofs'
    AND (
      (SELECT public.get_user_role()) IN ('technician', 'courier', 'warehouse', 'admin', 'owner')
      OR (SELECT public.has_feature('DELIVERY'))
      OR (SELECT public.has_feature('MY_INVENTORY'))
      OR (SELECT public.has_feature('COURIER'))
    )
  );

DROP POLICY IF EXISTS delivery_proofs_write ON storage.objects;
CREATE POLICY delivery_proofs_feature_write ON storage.objects
  FOR INSERT TO authenticated
  WITH CHECK (
    bucket_id = 'delivery-proofs'
    AND (
      (SELECT public.get_user_role()) IN ('technician', 'courier')
      OR (SELECT public.has_feature('DELIVERY'))
      OR (SELECT public.has_feature('MY_INVENTORY'))
      OR (SELECT public.has_feature('COURIER'))
    )
  );

CREATE OR REPLACE FUNCTION public.guard_request_transition()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_role text := (SELECT public.get_user_role());
  v_actor uuid := (SELECT auth.uid());
  v_can_deliver boolean := v_role IN ('technician', 'courier')
    OR (SELECT public.has_feature('DELIVERY'))
    OR (SELECT public.has_feature('MY_INVENTORY'))
    OR (SELECT public.has_feature('COURIER'));
  v_allowed boolean := false;
BEGIN
  -- Non-status edits retain their own RLS checks. Status changes must always
  -- pass through this role-and-owner-aware state machine.
  IF NEW.status IS NOT DISTINCT FROM OLD.status THEN
    RETURN NEW;
  END IF;

  v_allowed := CASE v_role
    WHEN 'client' THEN OLD.user_id = v_actor
      AND ((OLD.status IN ('submitted', 'priced', 'approved') AND NEW.status = 'cancelled')
        OR (OLD.status = 'delivered' AND NEW.status IN ('completed', 'issue')))
    WHEN 'marketing' THEN (OLD.status = 'submitted' AND NEW.status = 'priced')
      OR (
        OLD.status = 'priced'
        AND NEW.status IN ('approved', 'rejected')
        AND current_setting('app.auto_approve_transition', true) = 'enabled'
      )
    WHEN 'boss' THEN OLD.status = 'priced' AND NEW.status IN ('approved', 'rejected')
    WHEN 'finance' THEN OLD.status = 'approved' AND NEW.status = 'invoice_ready'
    WHEN 'warehouse' THEN (OLD.status = 'invoice_ready' AND NEW.status = 'preparing')
      OR (OLD.status = 'preparing' AND NEW.status = 'ready')
    WHEN v_can_deliver THEN (OLD.status = 'ready' AND NEW.status = 'on_delivery')
      OR (OLD.status = 'on_delivery' AND NEW.status = 'delivered')
    WHEN 'admin' THEN (OLD.status = 'issue' AND NEW.status = 'resolved')
      OR (OLD.status = 'delivered' AND NEW.status IN ('resolved', 'completed'))
    ELSE false
  END;

  IF NOT COALESCE(v_allowed, false) THEN
    RAISE EXCEPTION 'Role % cannot transition request from % to %', v_role, OLD.status, NEW.status
      USING ERRCODE = '42501';
  END IF;

  -- Audit fields are server-derived, never trusted from a browser payload.
  NEW.updated_by := v_actor;
  NEW.updated_at := now();
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS guard_request_transition ON public.requests;
CREATE TRIGGER guard_request_transition
  BEFORE UPDATE OF status ON public.requests
  FOR EACH ROW EXECUTE FUNCTION public.guard_request_transition();

REVOKE ALL ON FUNCTION public.guard_request_transition() FROM PUBLIC;

-- Auto approval is a business rule, not a browser-side role impersonation.
-- It runs under a definer function only after validating the real caller,
-- request branch, branch settings, debt limit, and historical spend.
CREATE OR REPLACE FUNCTION public.rpc_auto_approve_priced_request(
  p_order_id uuid,
  p_user_id uuid
) RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_request public.requests%ROWTYPE;
  v_client public.profiles%ROWTYPE;
  v_enabled boolean;
  v_min_spend numeric;
  v_default_limit numeric;
  v_total_spent numeric;
  v_next_status text;
BEGIN
  IF (SELECT auth.uid()) IS DISTINCT FROM p_user_id
    OR (SELECT public.get_user_role()) NOT IN ('marketing', 'boss', 'admin', 'owner') THEN
    RAISE EXCEPTION 'Unauthorized auto-approval attempt';
  END IF;

  SELECT * INTO v_request FROM public.requests WHERE id = p_order_id FOR UPDATE;
  IF NOT FOUND OR v_request.status <> 'priced'
    OR NOT (SELECT public.can_access_branch(v_request.branch_id)) THEN
    RAISE EXCEPTION 'Priced request is unavailable for auto approval';
  END IF;

  SELECT auto_approve_enabled, auto_approve_min_spend, auto_approve_default_limit
    INTO v_enabled, v_min_spend, v_default_limit
    FROM public.branches WHERE id = v_request.branch_id;
  IF NOT COALESCE(v_enabled, false) THEN RETURN 'skipped'; END IF;

  SELECT * INTO v_client FROM public.profiles WHERE id = v_request.user_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'Request client profile is missing'; END IF;

  IF COALESCE(v_client.debt_amount, 0) + COALESCE(v_request.total_price, 0)
       > COALESCE(v_client.debt_limit, v_default_limit) THEN
    v_next_status := 'rejected';
  ELSE
    SELECT COALESCE(sum(total_price), 0) INTO v_total_spent
      FROM public.requests
      WHERE user_id = v_request.user_id AND status IN ('completed', 'resolved');
    IF v_total_spent < COALESCE(v_min_spend, 0) THEN RETURN 'skipped'; END IF;
    v_next_status := 'approved';
  END IF;

  PERFORM set_config('app.auto_approve_transition', 'enabled', true);
  UPDATE public.requests
    SET status = v_next_status::public.request_status,
        rejection_reason = CASE WHEN v_next_status = 'rejected' THEN 'Automatically rejected: credit limit exceeded' ELSE rejection_reason END,
        updated_by = p_user_id,
        updated_at = now()
    WHERE id = p_order_id;
  RETURN v_next_status;
END;
$$;

REVOKE ALL ON FUNCTION public.rpc_auto_approve_priced_request(uuid, uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.rpc_auto_approve_priced_request(uuid, uuid) TO authenticated;

-- Executive read access does not imply identity-and-permission management.
-- Only the two administrative roles can alter another user's protected fields;
-- no one can elevate their own role, feature grants, or branch assignment.
CREATE OR REPLACE FUNCTION public.guard_profile_update()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_protected_change boolean;
  v_actor_role text := (SELECT public.get_user_role());
BEGIN
  v_protected_change := NEW.role IS DISTINCT FROM OLD.role
    OR NEW.features IS DISTINCT FROM OLD.features
    OR NEW.branch_id IS DISTINCT FROM OLD.branch_id
    OR NEW.is_branch_pinned IS DISTINCT FROM OLD.is_branch_pinned
    OR NEW.handled_by IS DISTINCT FROM OLD.handled_by
    OR NEW.client_type IS DISTINCT FROM OLD.client_type
    OR NEW.debt_amount IS DISTINCT FROM OLD.debt_amount
    OR NEW.debt_limit IS DISTINCT FROM OLD.debt_limit
    OR NEW.leave_balance IS DISTINCT FROM OLD.leave_balance
    OR NEW.is_active IS DISTINCT FROM OLD.is_active;

  IF v_protected_change THEN
    IF (SELECT auth.uid()) = OLD.id THEN
      RAISE EXCEPTION 'Users cannot change their own protected profile fields';
    END IF;
    IF v_actor_role NOT IN ('admin', 'owner') THEN
      RAISE EXCEPTION 'Only administrators can change protected profile fields';
    END IF;
    IF OLD.role = 'owner' AND v_actor_role <> 'owner' THEN
      RAISE EXCEPTION 'Only an owner can modify another owner profile';
    END IF;
  END IF;
  RETURN NEW;
END;
$$;

DROP POLICY IF EXISTS "profiles_executive_update" ON public.profiles;
DROP POLICY IF EXISTS profiles_admin_update ON public.profiles;
CREATE POLICY profiles_administrative_update ON public.profiles
  FOR UPDATE TO authenticated
  USING ((SELECT public.get_user_role()) IN ('admin', 'owner'))
  WITH CHECK ((SELECT public.get_user_role()) IN ('admin', 'owner'));

REVOKE ALL ON FUNCTION public.guard_profile_update() FROM PUBLIC;

-- Remove legacy feature grants that were never valid for the faktur role and
-- expose its actual operational screen. Existing custom order is preserved.
UPDATE public.profiles
SET features = ARRAY[
  'COMPANY', 'FAKTUR_TASKS', 'CLAIMS', 'TIME_OFF', 'ATTENDANCE', 'MY_PROFILE', 'SETTINGS'
]::text[]
WHERE role::text = 'faktur'
  AND (features IS NULL OR features && ARRAY['FINANCE', 'CATALOG']::text[]);

-- A payment can be retried by the browser. The financial ledger must still
-- record an invoice settlement once only, even if two requests race.
CREATE UNIQUE INDEX IF NOT EXISTS uq_financial_transactions_invoice_payment
  ON public.financial_transactions (reference_table, reference_id)
  WHERE reference_table = 'invoices'
    AND transaction_type = 'invoice_payment';
