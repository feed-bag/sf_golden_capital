public with sharing class ApprovalSupabaseRelay implements Queueable, Database.AllowsCallouts {

    @TestVisible private static Integer MAX_ATTEMPTS = 3;
    @TestVisible private static final String ENDPOINT = 'callout:Supabase/functions/v1/approval-sync';
    @TestVisible private static final Integer TIMEOUT_MS = 60000;

    private final Set<Id> upsertIds;
    private final Set<Id> deleteIds;
    private final Integer attempt;

    public ApprovalSupabaseRelay(Set<Id> upsertIds, Set<Id> deleteIds) {
        this(upsertIds, deleteIds, 1);
    }

    @TestVisible
    private ApprovalSupabaseRelay(Set<Id> upsertIds, Set<Id> deleteIds, Integer attempt) {
        this.upsertIds = upsertIds == null ? new Set<Id>() : upsertIds;
        this.deleteIds = deleteIds == null ? new Set<Id>() : deleteIds;
        this.attempt = attempt == null ? 1 : attempt;
    }

    public void execute(QueueableContext ctx) {
        Map<Id, Approval__c> records = new Map<Id, Approval__c>();
        if (!upsertIds.isEmpty()) {
            records = new Map<Id, Approval__c>([
                SELECT Id, Opportunity__c, Status__c, Contract_Type__c, Funding_Source__c,
                       Purchase_Price__c, Net_Funded_Amount__c, Down_Payment__c, Down_Payment_Percent__c,
                       Doc_Fee__c, Title_Fee__c, GC_Revenue__c, Rep_Commission__c, Points__c,
                       Periodic_Payment__c, Payment_Frequency__c, Term_Length__c, Expiration__c,
                       Notes__c, App_Submission__c, Sales_Representative__c,
                       CreatedDate, LastModifiedDate
                  FROM Approval__c
                 WHERE Id IN :upsertIds
            ]);
        }

        List<Map<String, Object>> events = new List<Map<String, Object>>();
        for (Id recId : upsertIds) {
            Approval__c rec = records.get(recId);
            if (rec == null) {
                events.add(new Map<String, Object>{
                    'recordId' => String.valueOf(recId),
                    'changeType' => 'DELETE',
                    'record' => null
                });
            } else {
                events.add(new Map<String, Object>{
                    'recordId' => String.valueOf(recId),
                    'changeType' => 'UPSERT',
                    'record' => rec
                });
            }
        }
        for (Id recId : deleteIds) {
            events.add(new Map<String, Object>{
                'recordId' => String.valueOf(recId),
                'changeType' => 'DELETE',
                'record' => null
            });
        }

        if (events.isEmpty()) {
            return;
        }

        String body = JSON.serialize(new Map<String, Object>{ 'events' => events });

        HttpRequest req = new HttpRequest();
        req.setEndpoint(ENDPOINT);
        req.setMethod('POST');
        req.setHeader('Content-Type', 'application/json');
        req.setBody(body);
        req.setTimeout(TIMEOUT_MS);

        Integer status;
        String errMsg;
        try {
            HttpResponse res = new Http().send(req);
            status = res.getStatusCode();
            if (status >= 200 && status < 300) {
                return;
            }
            errMsg = 'HTTP ' + status + ': ' + res.getBody();
        } catch (Exception e) {
            errMsg = e.getTypeName() + ': ' + e.getMessage();
        }

        Boolean transientErr = (status == null) || (status >= 500);
        if (transientErr && attempt < MAX_ATTEMPTS) {
            System.enqueueJob(new ApprovalSupabaseRelay(upsertIds, deleteIds, attempt + 1));
            return;
        }
        logFailure(events, errMsg);
    }

    private void logFailure(List<Map<String, Object>> events, String errMsg) {
        List<Approval_Sync_Failure__c> rows = new List<Approval_Sync_Failure__c>();
        for (Map<String, Object> evt : events) {
            rows.add(new Approval_Sync_Failure__c(
                Record_Id__c = (String) evt.get('recordId'),
                Change_Type__c = (String) evt.get('changeType'),
                Error__c = errMsg,
                Attempt__c = attempt,
                Payload__c = JSON.serialize(evt)
            ));
        }
        if (!rows.isEmpty()) {
            insert rows;
        }
        System.debug(LoggingLevel.ERROR, 'ApprovalSupabaseRelay failed after attempt ' + attempt + ': ' + errMsg);
    }
}
