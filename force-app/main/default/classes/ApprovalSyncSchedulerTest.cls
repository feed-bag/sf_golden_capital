@isTest
private class ApprovalSyncSchedulerTest {

    private class StaticMock implements HttpCalloutMock {
        public HttpRequest lastRequest;
        public HttpResponse respond(HttpRequest req) {
            this.lastRequest = req;
            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);
            res.setBody('{"ok":true}');
            res.setHeader('Content-Type', 'application/json');
            return res;
        }
    }

    private static Approval__c makeApproval() {
        Id lenderRtId = Schema.SObjectType.Account.getRecordTypeInfosByName().get('Lender Account').getRecordTypeId();
        Account funder = new Account(Name = 'Test Funder', RecordTypeId = lenderRtId);
        insert funder;
        Opportunity opp = new Opportunity(
            Name = 'Test Opp',
            StageName = 'Prospecting',
            CloseDate = Date.today().addDays(30)
        );
        insert opp;
        Approval__c a = new Approval__c(
            Opportunity__c = opp.Id,
            Purchase_Price__c = 10000,
            Net_Funded_Amount__c = 9000,
            Contract_Type__c = 'True Lease',
            Funding_Source__c = funder.Id
        );
        insert a;
        return a;
    }

    @isTest
    static void executeWithApprovalsEnqueuesRelay() {
        Approval__c a = makeApproval();
        StaticMock mock = new StaticMock();
        Test.setMock(HttpCalloutMock.class, mock);

        Test.startTest();
        new ApprovalSyncScheduler().execute(null);
        Test.stopTest();

        System.assertNotEquals(null, mock.lastRequest, 'callout should have been made');
        Map<String, Object> parsed = (Map<String, Object>) JSON.deserializeUntyped(mock.lastRequest.getBody());
        List<Object> events = (List<Object>) parsed.get('events');
        System.assertEquals(1, events.size());
        Map<String, Object> evt = (Map<String, Object>) events[0];
        System.assertEquals(String.valueOf(a.Id), (String) evt.get('recordId'));
        System.assertEquals('UPSERT', (String) evt.get('changeType'));
    }

    @isTest
    static void executeWithNoApprovalsIsNoop() {
        StaticMock mock = new StaticMock();
        Test.setMock(HttpCalloutMock.class, mock);

        Test.startTest();
        new ApprovalSyncScheduler().execute(null);
        Test.stopTest();

        System.assertEquals(null, mock.lastRequest, 'no callout should be made when there are no Approvals');
    }

    @isTest
    static void scheduleRegistersCronTrigger() {
        Test.startTest();
        String jobId = ApprovalSyncScheduler.schedule();
        Test.stopTest();

        CronTrigger ct = [SELECT Id, CronExpression, State FROM CronTrigger WHERE Id = :jobId];
        System.assertEquals(ApprovalSyncScheduler.DEFAULT_CRON, ct.CronExpression);
    }
}
