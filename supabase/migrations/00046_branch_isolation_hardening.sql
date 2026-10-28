-- ============================================================================
-- 00046: Branch-boundary enforcement
-- Database-level tenant isolation for branch-owned operational data.
-- Client-side activeBranchId is a presentation filter only; RLS is authoritative.
-- ============================================================================

CREATE OR REPLACE FUNCTION public.can_access_branch(p_branch_id uuid)
RETURNS boolean
LANGUAGE sql
SECURITY DEFINER
STABLE
SET search_path = public
AS $$
  SELECT (SELECT public.is_executive())
    OR (p_branch_id IS NOT NULL AND p_branch_id = (SELECT public.get_user_branch_id()));
$$;

REVOKE ALL ON FUNCTION public.can_access_branch(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.can_access_branch(uuid) TO authenticated;

-- ---------------------------------------------------------------------------
-- Requests and invoices were previously granted to all staff roles regardless
-- of branch. Replace those broad legacy policies with branch-aware policies.
-- ---------------------------------------------------------------------------
DROP POLICY IF EXISTS requests_isolation_policy ON public.requests;
DROP POLICY IF EXISTS requests_select ON public.requests;
CREATE POLICY requests_select ON public.requests
  FOR SELECT TO authenticated
  USING (
    user_id = (SELECT auth.uid())
    OR (
      (SELECT public.get_user_role()) <> 'client'
      AND (SELECT public.can_access_branch(branch_id))
    )
  );

DROP POLICY IF EXISTS requests_insert ON public.requests;
CREATE POLICY requests_branch_insert ON public.requests
  FOR INSERT TO authenticated
  WITH CHECK (
    user_id = (SELECT auth.uid())
    AND (SELECT public.can_access_branch(branch_id))
  );

DROP POLICY IF EXISTS requests_update ON public.requests;
CREATE POLICY requests_update ON public.requests
  FOR UPDATE TO authenticated
  USING (
    user_id = (SELECT auth.uid())
    OR (
      (SELECT public.get_user_role()) <> 'client'
      AND (SELECT public.can_access_branch(branch_id))
    )
  )
  WITH CHECK (
    user_id = (SELECT auth.uid())
    OR (
      (SELECT public.get_user_role()) <> 'client'
      AND (SELECT public.can_access_branch(branch_id))
    )
  );

DROP POLICY IF EXISTS request_items_update ON public.request_items;
CREATE POLICY request_items_update ON public.request_items
  FOR UPDATE TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM public.requests r
      WHERE r.id = request_id
        AND (SELECT public.can_access_branch(r.branch_id))
    )
  )
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM public.requests r
      WHERE r.id = request_id
        AND (SELECT public.can_access_branch(r.branch_id))
    )
  );

DROP POLICY IF EXISTS request_items_select ON public.request_items;
CREATE POLICY request_items_branch_read ON public.request_items
  FOR SELECT TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM public.requests r
      WHERE r.id = request_id
        AND (
          r.user_id = (SELECT auth.uid())
          OR ((SELECT public.get_user_role()) <> 'client' AND (SELECT public.can_access_branch(r.branch_id)))
        )
    )
  );

DROP POLICY IF EXISTS invoices_isolation_policy ON public.invoices;
DROP POLICY IF EXISTS invoices_select ON public.invoices;
DROP POLICY IF EXISTS invoices_manage ON public.invoices;
CREATE POLICY invoices_branch_read ON public.invoices
  FOR SELECT TO authenticated
  USING (
    (SELECT public.can_access_branch(branch_id))
    OR EXISTS (
      SELECT 1 FROM public.requests r
      WHERE r.id = order_id AND r.user_id = (SELECT auth.uid())
    )
  );

CREATE POLICY invoices_branch_manage ON public.invoices
  FOR ALL TO authenticated
  USING (
    (SELECT public.get_user_role()) IN ('finance', 'admin', 'owner')
    AND (SELECT public.can_access_branch(branch_id))
  )
  WITH CHECK (
    (SELECT public.get_user_role()) IN ('finance', 'admin', 'owner')
    AND (SELECT public.can_access_branch(branch_id))
  );

DROP POLICY IF EXISTS invoices_insert ON public.invoices;
CREATE POLICY invoices_insert ON public.invoices
  FOR INSERT TO authenticated
  WITH CHECK (
    (SELECT public.get_user_role()) IN ('finance', 'boss', 'admin', 'owner', 'faktur', 'tax', 'manager', 'director')
    AND (SELECT public.can_access_branch(branch_id))
  );

DROP POLICY IF EXISTS invoices_update ON public.invoices;
CREATE POLICY invoices_update ON public.invoices
  FOR UPDATE TO authenticated
  USING ((SELECT public.can_access_branch(branch_id)))
  WITH CHECK ((SELECT public.can_access_branch(branch_id)));

-- ---------------------------------------------------------------------------
-- Technician data: add an explicit branch key where the legacy schema lacked
-- one, backfill from the owning technician/reporter, and scope RLS by it.
-- ---------------------------------------------------------------------------
ALTER TABLE public.technician_areas
  ADD COLUMN IF NOT EXISTS branch_id uuid REFERENCES public.branches(id) ON DELETE RESTRICT;
ALTER TABLE public.service_issues
  ADD COLUMN IF NOT EXISTS branch_id uuid REFERENCES public.branches(id) ON DELETE RESTRICT;

CREATE OR REPLACE FUNCTION public.assign_service_issue_branch()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NEW.branch_id IS NULL THEN
    SELECT branch_id INTO NEW.branch_id FROM public.profiles WHERE id = NEW.reported_by;
  END IF;
  IF NEW.branch_id IS NULL THEN
    RAISE EXCEPTION 'A branch is required for service issues';
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS assign_service_issue_branch ON public.service_issues;
CREATE TRIGGER assign_service_issue_branch
  BEFORE INSERT ON public.service_issues
  FOR EACH ROW EXECUTE FUNCTION public.assign_service_issue_branch();

UPDATE public.technician_areas a
SET branch_id = p.branch_id
FROM public.profiles p
WHERE a.branch_id IS NULL AND p.id = a.technician_id AND p.branch_id IS NOT NULL;

UPDATE public.service_issues i
SET branch_id = COALESCE(a.branch_id, p.branch_id)
FROM public.profiles p
LEFT JOIN public.technician_areas a ON a.id = i.area_id
WHERE i.branch_id IS NULL AND p.id = i.reported_by;

CREATE INDEX IF NOT EXISTS idx_technician_areas_branch ON public.technician_areas(branch_id);
CREATE INDEX IF NOT EXISTS idx_service_issues_branch ON public.service_issues(branch_id);

DROP POLICY IF EXISTS tech_areas_select ON public.technician_areas;
CREATE POLICY tech_areas_select ON public.technician_areas
  FOR SELECT TO authenticated
  USING (
    technician_id = (SELECT auth.uid())
    OR (SELECT public.is_executive())
    OR (
      (SELECT public.get_user_role()) = 'technician'
      AND (SELECT public.can_access_branch(branch_id))
    )
  );

DROP POLICY IF EXISTS service_issues_select ON public.service_issues;
DROP POLICY IF EXISTS service_issues_isolation_policy ON public.service_issues;
CREATE POLICY service_issues_select ON public.service_issues
  FOR SELECT TO authenticated
  USING (
    reported_by = (SELECT auth.uid())
    OR (SELECT public.is_executive())
    OR (
      (SELECT public.get_user_role()) = 'technician'
      AND (SELECT public.can_access_branch(branch_id))
    )
  );

DROP POLICY IF EXISTS service_issues_insert ON public.service_issues;
CREATE POLICY service_issues_insert ON public.service_issues
  FOR INSERT TO authenticated
  WITH CHECK (
    reported_by = (SELECT auth.uid())
    AND (branch_id IS NULL OR (SELECT public.can_access_branch(branch_id)))
  );

DROP POLICY IF EXISTS service_issues_update ON public.service_issues;
CREATE POLICY service_issues_update ON public.service_issues
  FOR UPDATE TO authenticated
  USING (
    assigned_to = (SELECT auth.uid())
    OR (SELECT public.is_executive())
  )
  WITH CHECK (
    (SELECT public.is_executive())
    OR (assigned_to = (SELECT auth.uid()) AND (SELECT public.can_access_branch(branch_id)))
  );

DROP POLICY IF EXISTS requests_courier_select ON public.requests;
CREATE POLICY requests_courier_branch_read ON public.requests
  FOR SELECT TO authenticated
  USING (
    (SELECT public.get_user_role()) = 'courier'
    AND status IN ('ready', 'on_delivery', 'delivered')
    AND (SELECT public.can_access_branch(branch_id))
  );

DROP POLICY IF EXISTS requests_courier_update ON public.requests;
CREATE POLICY requests_courier_branch_update ON public.requests
  FOR UPDATE TO authenticated
  USING (
    (SELECT public.get_user_role()) = 'courier'
    AND (SELECT public.can_access_branch(branch_id))
    AND (status = 'ready' OR (status IN ('on_delivery', 'delivered') AND assigned_courier_id = (SELECT auth.uid())))
  )
  WITH CHECK (
    (SELECT public.get_user_role()) = 'courier'
    AND (SELECT public.can_access_branch(branch_id))
  );

DROP POLICY IF EXISTS issue_logs_select ON public.service_issue_logs;
CREATE POLICY issue_logs_select ON public.service_issue_logs
  FOR SELECT TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM public.service_issues i
      WHERE i.id = issue_id
        AND (
          i.reported_by = (SELECT auth.uid())
          OR (SELECT public.is_executive())
          OR ((SELECT public.get_user_role()) = 'technician' AND (SELECT public.can_access_branch(i.branch_id)))
        )
    )
  );

-- Equipment and PM branch ownership is derived from the product's branch.
DROP POLICY IF EXISTS "Technicians can view all assets" ON public.equipment_assets;
DROP POLICY IF EXISTS "Staff can manage assets" ON public.equipment_assets;
CREATE POLICY equipment_assets_branch_read ON public.equipment_assets
  FOR SELECT TO authenticated
  USING (
    client_id = (SELECT auth.uid())
    OR (
      (SELECT public.get_user_role()) = 'technician'
      AND EXISTS (
        SELECT 1 FROM public.products p
        WHERE p.id = product_id AND (SELECT public.can_access_branch(p.branch_id))
      )
    )
    OR (SELECT public.is_executive())
  );

CREATE POLICY equipment_assets_branch_manage ON public.equipment_assets
  FOR ALL TO authenticated
  USING (
    (SELECT public.is_executive())
    OR (
      (SELECT public.get_user_role()) = 'warehouse'
      AND EXISTS (
        SELECT 1 FROM public.products p
        WHERE p.id = product_id AND (SELECT public.can_access_branch(p.branch_id))
      )
    )
  )
  WITH CHECK (
    (SELECT public.is_executive())
    OR (
      (SELECT public.get_user_role()) = 'warehouse'
      AND EXISTS (
        SELECT 1 FROM public.products p
        WHERE p.id = product_id AND (SELECT public.can_access_branch(p.branch_id))
      )
    )
  );

DROP POLICY IF EXISTS "Technicians can view all pm schedules" ON public.pm_schedules;
DROP POLICY IF EXISTS "Technicians can update assigned pm schedules" ON public.pm_schedules;
DROP POLICY IF EXISTS "Staff can manage pm schedules" ON public.pm_schedules;
CREATE POLICY pm_schedules_branch_read ON public.pm_schedules
  FOR SELECT TO authenticated
  USING (
    EXISTS (
      SELECT 1
      FROM public.equipment_assets e
      JOIN public.products p ON p.id = e.product_id
      WHERE e.id = asset_id
        AND (
          e.client_id = (SELECT auth.uid())
          OR (SELECT public.is_executive())
          OR ((SELECT public.get_user_role()) = 'technician' AND (SELECT public.can_access_branch(p.branch_id)))
        )
    )
  );

CREATE POLICY pm_schedules_branch_update ON public.pm_schedules
  FOR UPDATE TO authenticated
  USING (
    (SELECT public.is_executive())
    OR (
      technician_id = (SELECT auth.uid())
      AND EXISTS (
        SELECT 1 FROM public.equipment_assets e
        JOIN public.products p ON p.id = e.product_id
        WHERE e.id = asset_id AND (SELECT public.can_access_branch(p.branch_id))
      )
    )
  )
  WITH CHECK (
    (SELECT public.is_executive())
    OR (
      technician_id = (SELECT auth.uid())
      AND EXISTS (
        SELECT 1 FROM public.equipment_assets e
        JOIN public.products p ON p.id = e.product_id
        WHERE e.id = asset_id AND (SELECT public.can_access_branch(p.branch_id))
      )
    )
  );

-- Claims must not be visible or mutable by an approver in another branch.
DROP POLICY IF EXISTS "Approvers and Claim Officers can view all requests" ON public.company_requests;
CREATE POLICY company_requests_branch_read ON public.company_requests
  FOR SELECT TO authenticated
  USING (
    created_by = (SELECT auth.uid())
    OR (
      (SELECT public.get_user_role()) IN ('owner', 'director', 'claim_officer', 'admin')
      AND (SELECT public.can_access_branch(branch_id))
    )
  );

DROP POLICY IF EXISTS "Users can create requests" ON public.company_requests;
CREATE POLICY company_requests_branch_insert ON public.company_requests
  FOR INSERT TO authenticated
  WITH CHECK (
    created_by = (SELECT auth.uid())
    AND (SELECT public.can_access_branch(branch_id))
  );

DROP POLICY IF EXISTS "Users can update their own requests if SUBMITTED or PENDING negotiation" ON public.company_requests;
CREATE POLICY company_requests_owner_update ON public.company_requests
  FOR UPDATE TO authenticated
  USING (
    created_by = (SELECT auth.uid())
    AND status IN ('SUBMITTED', 'PENDING', 'READY_FOR_CASH')
    AND (SELECT public.can_access_branch(branch_id))
  )
  WITH CHECK (
    created_by = (SELECT auth.uid())
    AND status IN ('SUBMITTED', 'PENDING', 'READY_FOR_CASH')
    AND (SELECT public.can_access_branch(branch_id))
  );

DROP POLICY IF EXISTS "Approvers and Claim Officers can update requests" ON public.company_requests;
CREATE POLICY company_requests_branch_update ON public.company_requests
  FOR UPDATE TO authenticated
  USING (
    (SELECT public.get_user_role()) IN ('owner', 'director', 'claim_officer', 'admin')
    AND (SELECT public.can_access_branch(branch_id))
  )
  WITH CHECK (
    (SELECT public.get_user_role()) IN ('owner', 'director', 'claim_officer', 'admin')
    AND (SELECT public.can_access_branch(branch_id))
  );

DROP POLICY IF EXISTS "Users can view items of requests they can view" ON public.company_request_items;
CREATE POLICY company_request_items_branch_read ON public.company_request_items
  FOR SELECT TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM public.company_requests r
      WHERE r.id = request_id
        AND (
          r.created_by = (SELECT auth.uid())
          OR (
            (SELECT public.get_user_role()) IN ('owner', 'director', 'claim_officer', 'admin')
            AND (SELECT public.can_access_branch(r.branch_id))
          )
        )
    )
  );

DROP POLICY IF EXISTS "Anyone can view history of their accessible requests" ON public.company_request_history;
CREATE POLICY company_request_history_branch_read ON public.company_request_history
  FOR SELECT TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM public.company_requests r
      WHERE r.id = request_id
        AND (
          r.created_by = (SELECT auth.uid())
          OR (
            (SELECT public.get_user_role()) IN ('owner', 'director', 'claim_officer', 'admin')
            AND (SELECT public.can_access_branch(r.branch_id))
          )
        )
    )
  );

DROP POLICY IF EXISTS "Users can insert history" ON public.company_request_history;
CREATE POLICY company_request_history_branch_insert ON public.company_request_history
  FOR INSERT TO authenticated
  WITH CHECK (
    actor_id = (SELECT auth.uid())
    AND EXISTS (
      SELECT 1 FROM public.company_requests r
      WHERE r.id = request_id
        AND (
          r.created_by = (SELECT auth.uid())
          OR (
            (SELECT public.get_user_role()) IN ('owner', 'director', 'claim_officer', 'admin')
            AND (SELECT public.can_access_branch(r.branch_id))
          )
        )
    )
  );

-- SECURITY DEFINER RPCs bypass table RLS. Enforce branch authorization at the
-- RPC boundary for the one caller-controlled branch argument.
CREATE OR REPLACE FUNCTION public.rpc_monthly_closing(p_branch_id uuid, p_month text, p_user_id uuid)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE v_period date := to_date(p_month || '-01', 'YYYY-MM-DD'); v_revenue numeric := 0; v_paid integer := 0; v_unpaid integer := 0;
BEGIN
  IF (SELECT auth.uid()) IS DISTINCT FROM p_user_id
    OR (SELECT public.get_user_role()) NOT IN ('finance', 'admin', 'owner')
    OR NOT (SELECT public.can_access_branch(p_branch_id)) THEN
    RAISE EXCEPTION 'Unauthorized monthly closing';
  END IF;
  SELECT coalesce(sum(amount), 0) INTO v_revenue FROM public.financial_transactions
    WHERE branch_id = p_branch_id AND direction = 'inflow' AND created_at >= v_period AND created_at < v_period + interval '1 month';
  SELECT count(*) FILTER (WHERE status = 'paid'), count(*) FILTER (WHERE status IN ('draft','issued','overdue')) INTO v_paid, v_unpaid
    FROM public.invoices WHERE branch_id = p_branch_id;
  INSERT INTO public.monthly_closing (branch_id, month, year, total_revenue, total_tax, orders_count, paid_invoices, unpaid_invoices, closed_by)
  SELECT p_branch_id, extract(month FROM v_period)::integer, extract(year FROM v_period)::integer, v_revenue, coalesce(sum(tax_amount), 0), count(*), v_paid, v_unpaid, p_user_id
  FROM public.invoices WHERE branch_id = p_branch_id AND created_at >= v_period AND created_at < v_period + interval '1 month'
  ON CONFLICT (branch_id, month, year) DO UPDATE SET total_revenue = excluded.total_revenue, total_tax = excluded.total_tax, orders_count = excluded.orders_count, paid_invoices = excluded.paid_invoices, unpaid_invoices = excluded.unpaid_invoices, closed_by = excluded.closed_by, updated_at = now();
  RETURN true;
END;
$$;

REVOKE ALL ON FUNCTION public.rpc_monthly_closing(uuid, text, uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.rpc_monthly_closing(uuid, text, uuid) TO authenticated;
