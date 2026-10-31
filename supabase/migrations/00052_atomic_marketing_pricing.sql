-- ============================================================================
-- 00052: Atomic marketing pricing
-- Price snapshots and discounts are derived from the active server-side price
-- list. The browser may select a mode and discount, but may never supply a
-- unit price or aggregate order total.
-- ============================================================================

ALTER TABLE public.request_items
  ADD COLUMN IF NOT EXISTS discount_percentage numeric(5,2) NOT NULL DEFAULT 0;
ALTER TABLE public.request_items
  DROP CONSTRAINT IF EXISTS request_items_discount_percentage_range;
ALTER TABLE public.request_items
  ADD CONSTRAINT request_items_discount_percentage_range
  CHECK (discount_percentage >= 0 AND discount_percentage <= 100);

CREATE OR REPLACE FUNCTION public.rpc_price_request(
  p_request_id uuid,
  p_user_id uuid,
  p_pricing_mode text,
  p_note text,
  p_discount_type public.discount_type DEFAULT NULL,
  p_discount_value numeric DEFAULT 0,
  p_discount_reason text DEFAULT NULL,
  p_item_discounts jsonb DEFAULT '{}'::jsonb
) RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_request public.requests%ROWTYPE;
  v_item record;
  v_unit_price numeric(15,2);
  v_item_discount numeric(5,2);
  v_total numeric(15,2) := 0;
  v_discount_amount numeric(15,2) := 0;
BEGIN
  IF (SELECT auth.uid()) IS DISTINCT FROM p_user_id
    OR (SELECT public.get_user_role()) <> 'marketing' THEN
    RAISE EXCEPTION 'Unauthorized request pricing' USING ERRCODE = '42501';
  END IF;
  IF p_pricing_mode NOT IN ('regular', 'kso', 'cost_per_test') THEN
    RAISE EXCEPTION 'Unsupported pricing mode';
  END IF;
  IF jsonb_typeof(p_item_discounts) IS DISTINCT FROM 'object' THEN
    RAISE EXCEPTION 'Item discounts must be an object keyed by request-item id';
  END IF;
  IF p_discount_value IS NULL OR p_discount_value < 0
    OR (p_discount_type IS NOT NULL AND p_discount_type = 'percent' AND p_discount_value > 100) THEN
    RAISE EXCEPTION 'Invalid order discount';
  END IF;
  IF p_discount_value > 0 AND p_discount_type IS NULL THEN
    RAISE EXCEPTION 'A discount type is required when a discount value is set';
  END IF;

  SELECT * INTO v_request
  FROM public.requests
  WHERE id = p_request_id
  FOR UPDATE;

  IF NOT FOUND OR v_request.status <> 'submitted'
    OR NOT (SELECT public.can_access_branch(v_request.branch_id)) THEN
    RAISE EXCEPTION 'Submitted request is unavailable for pricing';
  END IF;

  PERFORM set_config('app.request_pricing_update', 'enabled', true);

  FOR v_item IN
    SELECT id, product_id, quantity
    FROM public.request_items
    WHERE request_id = p_request_id
    ORDER BY id
  LOOP
    SELECT CASE p_pricing_mode
      WHEN 'regular' THEN price_regular
      WHEN 'kso' THEN price_kso
      WHEN 'cost_per_test' THEN price_cost_per_test
    END
    INTO v_unit_price
    FROM public.price_list
    WHERE product_id = v_item.product_id
      AND is_active = true;

    IF v_unit_price IS NULL OR v_unit_price < 0 THEN
      RAISE EXCEPTION 'An active % price is required for product %', p_pricing_mode, v_item.product_id;
    END IF;

    BEGIN
      v_item_discount := COALESCE((p_item_discounts ->> v_item.id::text)::numeric, 0);
    EXCEPTION WHEN invalid_text_representation THEN
      RAISE EXCEPTION 'Item discount for % must be numeric', v_item.id;
    END;
    IF v_item_discount < 0 OR v_item_discount > 100 THEN
      RAISE EXCEPTION 'Item discount for % must be between 0 and 100', v_item.id;
    END IF;

    UPDATE public.request_items
    SET price_at_order = round(v_unit_price, 2),
        discount_percentage = round(v_item_discount, 2),
        updated_at = now()
    WHERE id = v_item.id;

    v_total := v_total + round(v_unit_price * v_item.quantity * (1 - v_item_discount / 100), 2);
  END LOOP;

  IF NOT EXISTS (SELECT 1 FROM public.request_items WHERE request_id = p_request_id) THEN
    RAISE EXCEPTION 'A request must contain at least one item before pricing';
  END IF;

  IF p_discount_type = 'percent' THEN
    v_discount_amount := round(v_total * p_discount_value / 100, 2);
  ELSIF p_discount_type = 'fixed' THEN
    v_discount_amount := LEAST(round(p_discount_value, 2), v_total);
  END IF;

  UPDATE public.requests
  SET total_price = round(v_total, 2),
      note = NULLIF(trim(COALESCE(p_note, '')), ''),
      discount_type = CASE WHEN p_discount_value > 0 THEN p_discount_type ELSE NULL END,
      discount_value = CASE WHEN p_discount_value > 0 THEN round(p_discount_value, 2) ELSE 0 END,
      discount_amount = v_discount_amount,
      discount_reason = CASE
        WHEN p_discount_value > 0 THEN NULLIF(trim(COALESCE(p_discount_reason, '')), '')
        ELSE NULL
      END,
      discounted_by = CASE WHEN p_discount_value > 0 THEN p_user_id ELSE NULL END,
      status = 'priced',
      priced_at = now(),
      updated_by = p_user_id,
      updated_at = now()
  WHERE id = p_request_id;

  RETURN p_request_id;
END;
$$;

REVOKE ALL ON FUNCTION public.rpc_price_request(uuid, uuid, text, text, public.discount_type, numeric, text, jsonb) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.rpc_price_request(uuid, uuid, text, text, public.discount_type, numeric, text, jsonb) TO authenticated;
