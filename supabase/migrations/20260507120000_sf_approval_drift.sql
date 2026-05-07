-- Reconcile sf_approval with Salesforce Approval__c after Broker_Fee_Revenue__c
-- retirement and Down_Payment_Percent / GC_Revenue / Rep_Commission /
-- Sales_Representative additions.

ALTER TABLE public.sf_approval
  ADD COLUMN IF NOT EXISTS down_payment_percent     numeric,
  ADD COLUMN IF NOT EXISTS gc_revenue               numeric,
  ADD COLUMN IF NOT EXISTS rep_commission           numeric,
  ADD COLUMN IF NOT EXISTS sales_representative_id  text;

COMMENT ON COLUMN public.sf_approval.down_payment_percent IS
  'Approval__c.Down_Payment_Percent__c';
COMMENT ON COLUMN public.sf_approval.gc_revenue IS
  'Approval__c.GC_Revenue__c (replaces retired Broker_Fee_Revenue__c)';
COMMENT ON COLUMN public.sf_approval.rep_commission IS
  'Approval__c.Rep_Commission__c';
COMMENT ON COLUMN public.sf_approval.sales_representative_id IS
  'Approval__c.Sales_Representative__c (User Id)';
COMMENT ON COLUMN public.sf_approval.broker_fee_revenue IS
  'DEPRECATED 2026-05-07: Salesforce field retired. No longer populated. Schedule drop after migration window.';

CREATE INDEX IF NOT EXISTS sf_approval_synced_at_idx
  ON public.sf_approval (synced_at);
