-- The sf_approval sync runs as service_role via the approval-sync edge function.
-- Prior migration (grant_select_sf_approval_and_template_item, 2026-05-02) only
-- granted SELECT, blocking the writes the SF -> Supabase sync needs.
GRANT INSERT, UPDATE, DELETE ON public.sf_approval TO service_role;
