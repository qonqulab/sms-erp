-- ============================================================================
-- 00049: Claim amount integrity
-- Never trust totals sent by a browser. Line totals and request headers are
-- calculated in Postgres from the persisted quantities and unit prices.
-- ============================================================================

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'company_request_items_quantity_positive') THEN
    ALTER TABLE public.company_request_items
      ADD CONSTRAINT company_request_items_quantity_positive CHECK (quantity > 0);
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'company_request_items_price_nonnegative') THEN
    ALTER TABLE public.company_request_items
      ADD CONSTRAINT company_request_items_price_nonnegative CHECK (price_per_unit >= 0);
  END IF;
END;
$$;

CREATE OR REPLACE FUNCTION public.set_company_request_item_total()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  NEW.total_price := round(NEW.quantity * NEW.price_per_unit, 2);
  RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION public.sync_company_request_total()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_request_id uuid := COALESCE(NEW.request_id, OLD.request_id);
BEGIN
  PERFORM set_config('app.company_request_total_sync', 'enabled', true);
  UPDATE public.company_requests
  SET total_amount = COALESCE((
    SELECT sum(total_price)
    FROM public.company_request_items
    WHERE request_id = v_request_id
  ), 0)
  WHERE id = v_request_id;
  RETURN NULL;
END;
$$;

CREATE OR REPLACE FUNCTION public.guard_company_request_total()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NEW.total_amount IS DISTINCT FROM OLD.total_amount
    AND current_setting('app.company_request_total_sync', true) IS DISTINCT FROM 'enabled' THEN
    RAISE EXCEPTION 'Request total is derived from its line items';
  END IF;
  IF NEW.paid_amount < 0 OR NEW.paid_amount > NEW.total_amount THEN
    RAISE EXCEPTION 'Paid amount must be between zero and the request total';
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS set_company_request_item_total ON public.company_request_items;
CREATE TRIGGER set_company_request_item_total
  BEFORE INSERT OR UPDATE OF quantity, price_per_unit, total_price
  ON public.company_request_items
  FOR EACH ROW EXECUTE FUNCTION public.set_company_request_item_total();

DROP TRIGGER IF EXISTS sync_company_request_total ON public.company_request_items;
CREATE TRIGGER sync_company_request_total
  AFTER INSERT OR UPDATE OR DELETE ON public.company_request_items
  FOR EACH ROW EXECUTE FUNCTION public.sync_company_request_total();

DROP TRIGGER IF EXISTS guard_company_request_total ON public.company_requests;
CREATE TRIGGER guard_company_request_total
  BEFORE UPDATE ON public.company_requests
  FOR EACH ROW EXECUTE FUNCTION public.guard_company_request_total();

REVOKE ALL ON FUNCTION public.set_company_request_item_total() FROM PUBLIC;
REVOKE ALL ON FUNCTION public.sync_company_request_total() FROM PUBLIC;
REVOKE ALL ON FUNCTION public.guard_company_request_total() FROM PUBLIC;
