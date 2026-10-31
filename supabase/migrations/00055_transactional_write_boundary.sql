-- ============================================================================
-- 00055: Transactional write boundary
-- High-integrity records have dedicated, authenticated RPC workflows. Remove
-- raw authenticated writes so a REST caller cannot create partial orders,
-- alter request lines, forge invoices, or insert ledger entries.
-- ============================================================================

REVOKE INSERT, UPDATE, DELETE ON public.request_items FROM authenticated;
REVOKE INSERT, UPDATE, DELETE ON public.purchase_requests FROM authenticated;
REVOKE INSERT, UPDATE, DELETE ON public.purchase_request_items FROM authenticated;
REVOKE INSERT, UPDATE, DELETE ON public.invoices FROM authenticated;
REVOKE INSERT, UPDATE, DELETE ON public.financial_transactions FROM authenticated;
