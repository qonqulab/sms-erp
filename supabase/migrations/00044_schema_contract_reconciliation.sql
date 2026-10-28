-- ============================================================================
-- 00044: Schema contract reconciliation
-- Aligns the live Postgres contract with src/types, db queries, and services.
-- This is a forward-only, idempotent migration; it is safe on existing data.
-- ============================================================================

-- -----------------------------------------------------------------------------
-- Claims: the UI supports partial-payment proposals; the original table omitted
-- this persisted field.  The original trigger also used a non-existent function.
-- -----------------------------------------------------------------------------
ALTER TABLE public.company_requests
  ADD COLUMN IF NOT EXISTS proposed_amount numeric(15,2);

DROP TRIGGER IF EXISTS set_company_requests_updated_at ON public.company_requests;
CREATE TRIGGER set_company_requests_updated_at
  BEFORE UPDATE ON public.company_requests
  FOR EACH ROW EXECUTE FUNCTION public.update_updated_at();

-- -----------------------------------------------------------------------------
-- Frontend contracts that previously had types and query helpers but no schema.
-- -----------------------------------------------------------------------------
DO $$ BEGIN
  CREATE TYPE public.user_payment_method_type AS ENUM ('BANK', 'EWALLET');
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

CREATE TABLE IF NOT EXISTS public.user_payment_methods (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  type public.user_payment_method_type NOT NULL,
  provider text NOT NULL CHECK (length(trim(provider)) > 0),
  account_number text NOT NULL CHECK (length(trim(account_number)) > 0),
  account_name text NOT NULL CHECK (length(trim(account_name)) > 0),
  is_primary boolean NOT NULL DEFAULT false,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_user_payment_methods_user_created
  ON public.user_payment_methods (user_id, created_at DESC);
CREATE UNIQUE INDEX IF NOT EXISTS uq_user_payment_methods_primary
  ON public.user_payment_methods (user_id) WHERE is_primary;

DROP TRIGGER IF EXISTS set_user_payment_methods_updated_at ON public.user_payment_methods;
CREATE TRIGGER set_user_payment_methods_updated_at
  BEFORE UPDATE ON public.user_payment_methods
  FOR EACH ROW EXECUTE FUNCTION public.update_updated_at();

CREATE TABLE IF NOT EXISTS public.request_notes (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  request_id uuid NOT NULL REFERENCES public.requests(id) ON DELETE CASCADE,
  from_user_id uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  from_role text NOT NULL,
  to_role text NOT NULL,
  message text NOT NULL CHECK (length(trim(message)) > 0),
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_request_notes_request_created
  ON public.request_notes (request_id, created_at);
CREATE INDEX IF NOT EXISTS idx_request_notes_sender ON public.request_notes (from_user_id);

CREATE TABLE IF NOT EXISTS public.request_status_logs (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  request_id uuid NOT NULL REFERENCES public.requests(id) ON DELETE CASCADE,
  status public.request_status NOT NULL,
  actor_id uuid NOT NULL REFERENCES public.profiles(id) ON DELETE RESTRICT,
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_request_status_logs_request_created
  ON public.request_status_logs (request_id, created_at);
CREATE INDEX IF NOT EXISTS idx_request_status_logs_actor ON public.request_status_logs (actor_id);

CREATE TABLE IF NOT EXISTS public.staff_ratings (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  request_id uuid NOT NULL REFERENCES public.requests(id) ON DELETE CASCADE,
  status public.request_status NOT NULL,
  staff_id uuid NOT NULL REFERENCES public.profiles(id) ON DELETE RESTRICT,
  client_id uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  rating smallint NOT NULL CHECK (rating BETWEEN 1 AND 5),
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (request_id, status, client_id)
);
CREATE INDEX IF NOT EXISTS idx_staff_ratings_staff ON public.staff_ratings (staff_id);
CREATE INDEX IF NOT EXISTS idx_staff_ratings_client ON public.staff_ratings (client_id);

-- -----------------------------------------------------------------------------
-- RLS: ownership is enforced in the database, not merely in React.  Policies
-- use SELECT-wrapped auth calls and indexed keys for predictable performance.
-- -----------------------------------------------------------------------------
ALTER TABLE public.user_payment_methods ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.request_notes ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.request_status_logs ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.staff_ratings ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS user_payment_methods_owner ON public.user_payment_methods;
CREATE POLICY user_payment_methods_owner ON public.user_payment_methods
  FOR ALL TO authenticated
  USING (user_id = (SELECT auth.uid()))
  WITH CHECK (user_id = (SELECT auth.uid()));

DROP POLICY IF EXISTS request_notes_read ON public.request_notes;
CREATE POLICY request_notes_read ON public.request_notes
  FOR SELECT TO authenticated
  USING (
    from_user_id = (SELECT auth.uid())
    OR EXISTS (
      SELECT 1 FROM public.requests r
      WHERE r.id = request_id AND r.user_id = (SELECT auth.uid())
    )
    OR (SELECT public.get_user_role()) <> 'client'
  );
DROP POLICY IF EXISTS request_notes_insert ON public.request_notes;
CREATE POLICY request_notes_insert ON public.request_notes
  FOR INSERT TO authenticated
  WITH CHECK (from_user_id = (SELECT auth.uid()));

DROP POLICY IF EXISTS request_status_logs_read ON public.request_status_logs;
CREATE POLICY request_status_logs_read ON public.request_status_logs
  FOR SELECT TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM public.requests r
      WHERE r.id = request_id AND r.user_id = (SELECT auth.uid())
    )
    OR (SELECT public.get_user_role()) <> 'client'
  );
DROP POLICY IF EXISTS request_status_logs_insert ON public.request_status_logs;
CREATE POLICY request_status_logs_insert ON public.request_status_logs
  FOR INSERT TO authenticated
  WITH CHECK (actor_id = (SELECT auth.uid()));

DROP POLICY IF EXISTS staff_ratings_read ON public.staff_ratings;
CREATE POLICY staff_ratings_read ON public.staff_ratings
  FOR SELECT TO authenticated
  USING (client_id = (SELECT auth.uid()) OR staff_id = (SELECT auth.uid()) OR (SELECT public.is_executive()));
DROP POLICY IF EXISTS staff_ratings_insert ON public.staff_ratings;
CREATE POLICY staff_ratings_insert ON public.staff_ratings
  FOR INSERT TO authenticated
  WITH CHECK (
    client_id = (SELECT auth.uid())
    AND EXISTS (SELECT 1 FROM public.requests r WHERE r.id = request_id AND r.user_id = (SELECT auth.uid()))
  );
DROP POLICY IF EXISTS staff_ratings_update ON public.staff_ratings;
CREATE POLICY staff_ratings_update ON public.staff_ratings
  FOR UPDATE TO authenticated
  USING (client_id = (SELECT auth.uid()))
  WITH CHECK (client_id = (SELECT auth.uid()));

GRANT SELECT, INSERT, UPDATE, DELETE ON public.user_payment_methods TO authenticated;
GRANT SELECT, INSERT ON public.request_notes TO authenticated;
GRANT SELECT, INSERT ON public.request_status_logs TO authenticated;
GRANT SELECT, INSERT, UPDATE ON public.staff_ratings TO authenticated;

-- -----------------------------------------------------------------------------
-- Financial contract.  Earlier RPCs used retired columns (type/category/
-- created_by); the table and TypeScript contract use the names below.
-- -----------------------------------------------------------------------------
CREATE INDEX IF NOT EXISTS idx_financial_transactions_reference_table_id
  ON public.financial_transactions (reference_table, reference_id)
  WHERE reference_id IS NOT NULL AND reference_table IS NOT NULL;

-- The original unique key omitted branch_id, which made a closing for one
-- branch overwrite every other branch's closing for the same month.
ALTER TABLE public.monthly_closing
  DROP CONSTRAINT IF EXISTS monthly_closing_month_year_key;
CREATE UNIQUE INDEX IF NOT EXISTS uq_monthly_closing_branch_period
  ON public.monthly_closing (branch_id, month, year);

CREATE OR REPLACE FUNCTION public.rpc_create_invoice(
  p_order_id uuid, p_user_id uuid, p_total numeric, p_tax numeric
) RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_request public.requests%ROWTYPE;
  v_invoice_id uuid;
  v_invoice_number text;
BEGIN
  IF (SELECT auth.uid()) IS DISTINCT FROM p_user_id OR (SELECT public.get_user_role()) NOT IN ('finance', 'admin', 'owner') THEN
    RAISE EXCEPTION 'Unauthorized invoice creation';
  END IF;
  SELECT * INTO v_request FROM public.requests WHERE id = p_order_id FOR UPDATE;
  IF NOT FOUND OR v_request.status <> 'approved' THEN
    RAISE EXCEPTION 'Order must be approved before invoice creation';
  END IF;
  IF p_total < p_tax OR p_tax < 0 THEN RAISE EXCEPTION 'Invalid invoice totals'; END IF;

  SELECT public.generate_invoice_number() INTO v_invoice_number;
  INSERT INTO public.invoices (
    order_id, branch_id, invoice_number, subtotal, tax_rate, tax_amount,
    total, status, issued_at, due_date, created_by
  ) VALUES (
    p_order_id, v_request.branch_id, v_invoice_number, p_total - p_tax, 0.11,
    p_tax, p_total, 'issued', now(), now() + interval '14 days', p_user_id
  ) RETURNING id INTO v_invoice_id;

  UPDATE public.requests
  SET status = 'invoice_ready', invoice_id = v_invoice_id, invoice_ready_at = now(),
      updated_at = now(), updated_by = p_user_id
  WHERE id = p_order_id;
  RETURN v_invoice_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.rpc_prepare_order_stock(p_order_id uuid, p_user_id uuid)
RETURNS boolean
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_request public.requests%ROWTYPE; v_item record; v_balance integer;
BEGIN
  IF (SELECT auth.uid()) IS DISTINCT FROM p_user_id OR (SELECT public.get_user_role()) NOT IN ('warehouse', 'admin', 'owner') THEN
    RAISE EXCEPTION 'Unauthorized stock preparation';
  END IF;
  SELECT * INTO v_request FROM public.requests WHERE id = p_order_id FOR UPDATE;
  IF NOT FOUND OR v_request.status <> 'invoice_ready' THEN
    RAISE EXCEPTION 'Order status must be invoice_ready';
  END IF;

  FOR v_item IN SELECT product_id, quantity FROM public.request_items WHERE request_id = p_order_id ORDER BY product_id LOOP
    UPDATE public.products SET stock = stock - v_item.quantity, updated_at = now()
      WHERE id = v_item.product_id AND stock >= v_item.quantity RETURNING stock INTO v_balance;
    IF NOT FOUND THEN RAISE EXCEPTION 'Insufficient stock for product %', v_item.product_id; END IF;
    IF v_request.branch_id IS NOT NULL THEN
      UPDATE public.product_branch_stock SET stock = stock - v_item.quantity, updated_at = now()
        WHERE product_id = v_item.product_id AND branch_id = v_request.branch_id AND stock >= v_item.quantity;
      IF NOT FOUND THEN RAISE EXCEPTION 'Insufficient branch stock for product %', v_item.product_id; END IF;
    END IF;
    INSERT INTO public.inventory_logs (product_id, order_id, change, balance, movement_type, reason, created_by)
      VALUES (v_item.product_id, p_order_id, -v_item.quantity, v_balance, 'SALES_OUT', 'Stock consumed for order ' || p_order_id, p_user_id);
  END LOOP;
  UPDATE public.requests SET status = 'preparing', preparing_at = now(), updated_at = now(), updated_by = p_user_id WHERE id = p_order_id;
  RETURN true;
END;
$$;

CREATE OR REPLACE FUNCTION public.rpc_complete_delivery(p_delivery_id uuid, p_user_id uuid, p_proof_url text)
RETURNS boolean
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_order_id uuid;
BEGIN
  IF (SELECT auth.uid()) IS DISTINCT FROM p_user_id OR (SELECT public.get_user_role()) NOT IN ('courier', 'technician', 'admin', 'owner') THEN
    RAISE EXCEPTION 'Unauthorized delivery completion';
  END IF;
  UPDATE public.delivery_logs
  SET status = 'completed', proof_url = p_proof_url, delivered_at = now(), updated_at = now()
  WHERE id = p_delivery_id
  RETURNING order_id INTO v_order_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'Delivery log not found'; END IF;
  UPDATE public.requests SET status = 'delivered', delivered_at = now(), updated_at = now(), updated_by = p_user_id
    WHERE id = v_order_id AND status = 'on_delivery';
  RETURN true;
END;
$$;

CREATE OR REPLACE FUNCTION public.rpc_courier_take_delivery(p_delivery_id uuid, p_courier_id uuid)
RETURNS boolean
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_order_id uuid;
BEGIN
  IF (SELECT auth.uid()) IS DISTINCT FROM p_courier_id OR (SELECT public.get_user_role()) NOT IN ('courier', 'admin', 'owner') THEN
    RAISE EXCEPTION 'Unauthorized delivery assignment';
  END IF;
  UPDATE public.delivery_logs SET courier_id = p_courier_id, status = 'otw', updated_at = now()
    WHERE id = p_delivery_id AND courier_id IS NULL RETURNING order_id INTO v_order_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'Delivery is already assigned or does not exist'; END IF;
  UPDATE public.requests SET status = 'on_delivery', on_delivery_at = now(), updated_at = now(), updated_by = p_courier_id
    WHERE id = v_order_id AND status = 'ready';
  RETURN true;
END;
$$;

CREATE OR REPLACE FUNCTION public.rpc_execute_stock_transfer(p_transfer_id uuid, p_user_id uuid)
RETURNS boolean
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_transfer public.stock_transfers%ROWTYPE; v_item record; v_source_balance integer;
BEGIN
  IF (SELECT auth.uid()) IS DISTINCT FROM p_user_id OR (SELECT public.get_user_role()) NOT IN ('warehouse', 'purchasing', 'admin', 'owner') THEN
    RAISE EXCEPTION 'Unauthorized stock transfer';
  END IF;
  SELECT * INTO v_transfer FROM public.stock_transfers WHERE id = p_transfer_id FOR UPDATE;
  IF NOT FOUND OR v_transfer.status <> 'approved' THEN RAISE EXCEPTION 'Transfer must be approved before execution'; END IF;
  FOR v_item IN SELECT product_id, quantity FROM public.stock_transfer_items WHERE transfer_id = p_transfer_id ORDER BY product_id LOOP
    UPDATE public.product_branch_stock SET stock = stock - v_item.quantity, updated_at = now()
      WHERE product_id = v_item.product_id AND branch_id = v_transfer.from_branch_id AND stock >= v_item.quantity
      RETURNING stock INTO v_source_balance;
    IF NOT FOUND THEN RAISE EXCEPTION 'Insufficient source stock for product %', v_item.product_id; END IF;
    INSERT INTO public.product_branch_stock (product_id, branch_id, stock, min_stock)
      VALUES (v_item.product_id, v_transfer.to_branch_id, v_item.quantity, 0)
      ON CONFLICT (product_id, branch_id) DO UPDATE SET stock = public.product_branch_stock.stock + excluded.stock, updated_at = now();
    INSERT INTO public.inventory_logs (product_id, change, balance, movement_type, reason, created_by)
      VALUES (v_item.product_id, -v_item.quantity, v_source_balance, 'TRANSFER_OUT', 'Transfer outbound ' || p_transfer_id, p_user_id);
  END LOOP;
  UPDATE public.stock_transfers SET status = 'completed', received_by = p_user_id, received_at = now(), updated_at = now() WHERE id = p_transfer_id;
  RETURN true;
END;
$$;

CREATE OR REPLACE FUNCTION public.rpc_receive_purchase_order(p_po_id uuid, p_user_id uuid)
RETURNS boolean
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_po public.purchase_orders%ROWTYPE; v_item record; v_balance integer;
BEGIN
  IF (SELECT auth.uid()) IS DISTINCT FROM p_user_id OR (SELECT public.get_user_role()) NOT IN ('warehouse', 'purchasing', 'admin', 'owner') THEN
    RAISE EXCEPTION 'Unauthorized purchase receipt';
  END IF;
  SELECT * INTO v_po FROM public.purchase_orders WHERE id = p_po_id FOR UPDATE;
  IF NOT FOUND OR v_po.status IN ('received', 'cancelled') THEN RAISE EXCEPTION 'Purchase order is unavailable for receipt'; END IF;
  FOR v_item IN SELECT product_id, quantity FROM public.purchase_order_items WHERE purchase_order_id = p_po_id AND product_id IS NOT NULL ORDER BY product_id LOOP
    UPDATE public.products SET stock = stock + v_item.quantity, updated_at = now() WHERE id = v_item.product_id RETURNING stock INTO v_balance;
    INSERT INTO public.product_branch_stock (product_id, branch_id, stock, min_stock)
      VALUES (v_item.product_id, v_po.branch_id, v_item.quantity, 0)
      ON CONFLICT (product_id, branch_id) DO UPDATE SET stock = public.product_branch_stock.stock + excluded.stock, updated_at = now();
    UPDATE public.purchase_order_items SET received_quantity = quantity WHERE purchase_order_id = p_po_id AND product_id = v_item.product_id;
    INSERT INTO public.inventory_logs (product_id, change, balance, movement_type, reason, created_by)
      VALUES (v_item.product_id, v_item.quantity, v_balance, 'PURCHASE_IN', 'PO received ' || p_po_id, p_user_id);
  END LOOP;
  UPDATE public.purchase_orders SET status = 'received', received_at = now(), updated_at = now() WHERE id = p_po_id;
  RETURN true;
END;
$$;

CREATE OR REPLACE FUNCTION public.rpc_pay_supplier_invoice(p_invoice_id uuid, p_user_id uuid)
RETURNS boolean
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_invoice public.supplier_invoices%ROWTYPE;
BEGIN
  IF (SELECT auth.uid()) IS DISTINCT FROM p_user_id OR (SELECT public.get_user_role()) NOT IN ('finance', 'admin', 'owner') THEN
    RAISE EXCEPTION 'Unauthorized supplier payment';
  END IF;
  SELECT * INTO v_invoice FROM public.supplier_invoices WHERE id = p_invoice_id FOR UPDATE;
  IF NOT FOUND OR v_invoice.status = 'paid' THEN RAISE EXCEPTION 'Supplier invoice is unavailable for payment'; END IF;
  UPDATE public.supplier_invoices SET status = 'paid', paid_amount = total_amount, paid_at = now(), updated_at = now() WHERE id = p_invoice_id;
  INSERT INTO public.financial_transactions (branch_id, transaction_type, direction, amount, reference_id, reference_table, description, recorded_by)
  VALUES (v_invoice.branch_id, 'supplier_payment', 'outflow', v_invoice.total_amount, p_invoice_id, 'supplier_invoices', 'Paid supplier invoice ' || v_invoice.invoice_number, p_user_id);
  RETURN true;
END;
$$;

CREATE OR REPLACE FUNCTION public.rpc_pay_expense_claim(p_claim_id uuid, p_user_id uuid)
RETURNS boolean
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_claim public.expense_claims%ROWTYPE;
BEGIN
  IF (SELECT auth.uid()) IS DISTINCT FROM p_user_id OR (SELECT public.get_user_role()) NOT IN ('finance', 'claim_officer', 'admin', 'owner') THEN
    RAISE EXCEPTION 'Unauthorized expense-claim payment';
  END IF;
  SELECT * INTO v_claim FROM public.expense_claims WHERE id = p_claim_id FOR UPDATE;
  IF NOT FOUND OR v_claim.status IN ('paid', 'cancelled', 'rejected') THEN RAISE EXCEPTION 'Expense claim is unavailable for payment'; END IF;
  UPDATE public.expense_claims SET status = 'paid', paid_amount = amount, paid_at = now(), paid_by = p_user_id, updated_at = now() WHERE id = p_claim_id;
  INSERT INTO public.financial_transactions (branch_id, transaction_type, direction, amount, reference_id, reference_table, description, recorded_by)
  VALUES (v_claim.branch_id, 'expense_claim_payment', 'outflow', v_claim.amount, p_claim_id, 'expense_claims', 'Paid expense claim ' || p_claim_id, p_user_id);
  RETURN true;
END;
$$;

CREATE OR REPLACE FUNCTION public.rpc_monthly_closing(p_branch_id uuid, p_month text, p_user_id uuid)
RETURNS boolean
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_period date := to_date(p_month || '-01', 'YYYY-MM-DD'); v_revenue numeric := 0; v_paid integer := 0; v_unpaid integer := 0;
BEGIN
  IF (SELECT auth.uid()) IS DISTINCT FROM p_user_id OR (SELECT public.get_user_role()) NOT IN ('finance', 'admin', 'owner') THEN
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

REVOKE ALL ON FUNCTION public.rpc_create_invoice(uuid, uuid, numeric, numeric) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.rpc_prepare_order_stock(uuid, uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.rpc_complete_delivery(uuid, uuid, text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.rpc_courier_take_delivery(uuid, uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.rpc_execute_stock_transfer(uuid, uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.rpc_receive_purchase_order(uuid, uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.rpc_pay_supplier_invoice(uuid, uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.rpc_pay_expense_claim(uuid, uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.rpc_monthly_closing(uuid, text, uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.rpc_create_invoice(uuid, uuid, numeric, numeric), public.rpc_prepare_order_stock(uuid, uuid), public.rpc_complete_delivery(uuid, uuid, text), public.rpc_courier_take_delivery(uuid, uuid), public.rpc_execute_stock_transfer(uuid, uuid), public.rpc_receive_purchase_order(uuid, uuid), public.rpc_pay_supplier_invoice(uuid, uuid), public.rpc_pay_expense_claim(uuid, uuid), public.rpc_monthly_closing(uuid, text, uuid) TO authenticated;
