import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "jsr:@supabase/supabase-js@2";

type ChangeType = "UPSERT" | "DELETE";

interface ApprovalEvent {
  recordId: string;
  changeType: ChangeType;
  record: Record<string, unknown> | null;
}

interface RequestBody {
  events?: ApprovalEvent[];
}

interface EventResult {
  recordId: string;
  status: "ok" | "error";
  error?: string;
}

const FIELD_MAP: Record<string, string> = {
  Opportunity__c: "opportunity_id",
  Status__c: "status",
  Contract_Type__c: "contract_type",
  Funding_Source__c: "funding_source_id",
  Purchase_Price__c: "purchase_price",
  Net_Funded_Amount__c: "net_funded_amount",
  Down_Payment__c: "down_payment",
  Down_Payment_Percent__c: "down_payment_percent",
  Doc_Fee__c: "doc_fee",
  Title_Fee__c: "title_fee",
  GC_Revenue__c: "gc_revenue",
  Rep_Commission__c: "rep_commission",
  Points__c: "points",
  Periodic_Payment__c: "periodic_payment",
  Payment_Frequency__c: "payment_frequency",
  Term_Length__c: "term_length",
  Expiration__c: "expiration",
  Notes__c: "notes",
  App_Submission__c: "app_submission_id",
  Sales_Representative__c: "sales_representative_id",
  CreatedDate: "created_date",
  LastModifiedDate: "last_modified_date",
};

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SERVICE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
const SECRET_KEY = Deno.env.get("SUPABASE_SECRET_KEY") ?? "";

const json = (status: number, body: unknown) =>
  new Response(JSON.stringify(body), {
    status,
    headers: { "content-type": "application/json" },
  });

function transform(rec: Record<string, unknown>, recordId: string) {
  const out: Record<string, unknown> = {
    id: recordId,
    synced_at: new Date().toISOString(),
  };
  for (const [sfKey, col] of Object.entries(FIELD_MAP)) {
    if (sfKey in rec) out[col] = rec[sfKey];
  }
  return out;
}

Deno.serve(async (req: Request) => {
  if (req.method !== "POST") return json(405, { error: "method_not_allowed" });

  // Auth: match the apikey header against whichever auth key the project provides.
  // SF's Named Credential auto-generates its own Authorization (Bearer JWT) for
  // SecuredEndpoint-type NCs, so we authenticate on apikey alone, which the EC
  // populates via {!$Credential.Supabase.ServiceKey}. SUPABASE_SERVICE_ROLE_KEY
  // holds an sb_secret_* on new-key-model projects; SUPABASE_SECRET_KEY is the
  // alternate env var name on some projects — check both for portability.
  const apikey = req.headers.get("apikey") ?? "";
  const matchesServiceRole = !!SERVICE_KEY && apikey === SERVICE_KEY;
  const matchesSecret = !!SECRET_KEY && apikey === SECRET_KEY;
  if (!matchesServiceRole && !matchesSecret) {
    return json(401, { error: "unauthorized" });
  }
  const ACTIVE_KEY = matchesServiceRole ? SERVICE_KEY : SECRET_KEY;

  let body: RequestBody;
  try {
    body = await req.json();
  } catch {
    return json(400, { error: "invalid_json" });
  }
  if (!Array.isArray(body.events)) {
    return json(400, { error: "events_required" });
  }

  const supabase = createClient(SUPABASE_URL, ACTIVE_KEY, {
    auth: { persistSession: false },
  });

  const upserts: Record<string, unknown>[] = [];
  const deletes: string[] = [];
  const results: EventResult[] = [];

  for (const evt of body.events) {
    if (!evt?.recordId || !evt?.changeType) {
      results.push({
        recordId: evt?.recordId ?? "?",
        status: "error",
        error: "malformed_event",
      });
      continue;
    }
    if (evt.changeType === "DELETE") {
      deletes.push(evt.recordId);
    } else if (evt.changeType === "UPSERT" && evt.record) {
      upserts.push(transform(evt.record, evt.recordId));
    } else {
      results.push({
        recordId: evt.recordId,
        status: "error",
        error: "bad_change_type",
      });
    }
  }

  if (upserts.length) {
    const { error } = await supabase
      .from("sf_approval")
      .upsert(upserts, { onConflict: "id" });
    if (error) {
      const code = (error as { code?: string }).code;
      const isFk = code === "23503";
      return json(isFk ? 422 : 500, { error: error.message, code });
    }
    for (const u of upserts) {
      results.push({ recordId: String(u.id), status: "ok" });
    }
  }

  if (deletes.length) {
    const { error } = await supabase.from("sf_approval").delete().in("id", deletes);
    if (error) {
      return json(500, { error: error.message });
    }
    for (const id of deletes) {
      results.push({ recordId: id, status: "ok" });
    }
  }

  return json(200, { results });
});
