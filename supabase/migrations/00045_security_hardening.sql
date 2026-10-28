-- ============================================================================
-- 00045: Privilege-escalation and audit-log hardening
-- ============================================================================

-- A self-update policy scoped only by id permits clients to submit privileged
-- profile columns (role, feature grants, branch assignment, credit limits).
-- Keep legitimate self-service fields, but reject protected-column changes at
-- the database boundary. Executives retain their RLS-authorized management flow.
CREATE OR REPLACE FUNCTION public.guard_profile_update()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF (SELECT auth.uid()) = OLD.id THEN
    IF NEW.role IS DISTINCT FROM OLD.role
      OR NEW.features IS DISTINCT FROM OLD.features
      OR NEW.branch_id IS DISTINCT FROM OLD.branch_id
      OR NEW.is_branch_pinned IS DISTINCT FROM OLD.is_branch_pinned
      OR NEW.handled_by IS DISTINCT FROM OLD.handled_by
      OR NEW.client_type IS DISTINCT FROM OLD.client_type
      OR NEW.debt_amount IS DISTINCT FROM OLD.debt_amount
      OR NEW.debt_limit IS DISTINCT FROM OLD.debt_limit
      OR NEW.leave_balance IS DISTINCT FROM OLD.leave_balance
      OR NEW.is_active IS DISTINCT FROM OLD.is_active
    THEN
      RAISE EXCEPTION 'Protected profile fields can only be changed by an authorized workflow';
    END IF;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS guard_profile_update ON public.profiles;
CREATE TRIGGER guard_profile_update
  BEFORE UPDATE ON public.profiles
  FOR EACH ROW EXECUTE FUNCTION public.guard_profile_update();

-- Activity entries are audit evidence: never allow a caller to forge another
-- actor's history.
DROP POLICY IF EXISTS activity_logs_insert ON public.activity_logs;
CREATE POLICY activity_logs_insert ON public.activity_logs
  FOR INSERT TO authenticated
  WITH CHECK (user_id = (SELECT auth.uid()));

REVOKE ALL ON FUNCTION public.guard_profile_update() FROM PUBLIC;
