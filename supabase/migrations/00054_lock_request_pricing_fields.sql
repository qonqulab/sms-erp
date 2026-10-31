-- ============================================================================
-- 00054: Lock request pricing fields to the pricing transaction
-- RLS controls rows, but not individual columns. Prevent a branch user from
-- bypassing the pricing RPC with a REST update to prices, discounts, or total.
-- ============================================================================

CREATE OR REPLACE FUNCTION public.guard_request_pricing_fields()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF (
    NEW.total_price IS DISTINCT FROM OLD.total_price
    OR NEW.discount_type IS DISTINCT FROM OLD.discount_type
    OR NEW.discount_value IS DISTINCT FROM OLD.discount_value
    OR NEW.discount_amount IS DISTINCT FROM OLD.discount_amount
    OR NEW.discount_reason IS DISTINCT FROM OLD.discount_reason
    OR NEW.discounted_by IS DISTINCT FROM OLD.discounted_by
  ) AND current_setting('app.request_pricing_update', true) IS DISTINCT FROM 'enabled' THEN
    RAISE EXCEPTION 'Request pricing fields can only be changed through the pricing workflow'
      USING ERRCODE = '42501';
  END IF;
  RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION public.guard_request_item_pricing_fields()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF (
    NEW.price_at_order IS DISTINCT FROM OLD.price_at_order
    OR NEW.discount_percentage IS DISTINCT FROM OLD.discount_percentage
  ) AND current_setting('app.request_pricing_update', true) IS DISTINCT FROM 'enabled' THEN
    RAISE EXCEPTION 'Request-item pricing can only be changed through the pricing workflow'
      USING ERRCODE = '42501';
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS guard_request_pricing_fields ON public.requests;
CREATE TRIGGER guard_request_pricing_fields
  BEFORE UPDATE OF total_price, discount_type, discount_value, discount_amount, discount_reason, discounted_by
  ON public.requests
  FOR EACH ROW EXECUTE FUNCTION public.guard_request_pricing_fields();

DROP TRIGGER IF EXISTS guard_request_item_pricing_fields ON public.request_items;
CREATE TRIGGER guard_request_item_pricing_fields
  BEFORE UPDATE OF price_at_order, discount_percentage
  ON public.request_items
  FOR EACH ROW EXECUTE FUNCTION public.guard_request_item_pricing_fields();

REVOKE ALL ON FUNCTION public.guard_request_pricing_fields() FROM PUBLIC;
REVOKE ALL ON FUNCTION public.guard_request_item_pricing_fields() FROM PUBLIC;
