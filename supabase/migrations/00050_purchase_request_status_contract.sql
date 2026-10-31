-- ============================================================================
-- 00050: Purchase-request status contract
-- The application has always exposed a rejected outcome for procurement
-- approvals. Make that outcome part of the database enum before any workflow
-- RPC can persist it.
-- ============================================================================

ALTER TYPE public.purchase_request_status ADD VALUE IF NOT EXISTS 'rejected';
