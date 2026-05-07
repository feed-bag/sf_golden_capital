@isTest
private class ApprovalSupabaseRelayTest {

    private class StaticMock implements HttpCalloutMock {
        Integer status;
        String responseBody;
        public HttpRequest lastRequest;
        StaticMock(Integer status, String responseBody) {
            this.status = status;
            this.responseBody = responseBody;
        }
        public HttpResponse respond(HttpRequest req) {
            this.lastRequest = req;
            HttpResponse res = new HttpResponse();
            res.setStatusCode(status);
            res.setBody(responseBody == null ? '' : responseBody);
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
    static void successPathPostsExpectedShape() {
        Approval__c a = makeApproval();
        StaticMock mock = new StaticMock(200, '{"ok":true}');
        Test.setMock(HttpCalloutMock.class, mock);

        Test.startTest();
        System.enqueueJob(new ApprovalSupabaseRelay(new Set<Id>{ a.Id }, new Set<Id>()));
        Test.stopTest();

        System.assertNotEquals(null, mock.lastRequest, 'callout should have been made');
        System.assertEquals('POST', mock.lastRequest.getMethod());
        System.assert(mock.lastRequest.getEndpoint().endsWith('/functions/v1/approval-sync'),
            'endpoint should target the Edge Function: ' + mock.lastRequest.getEndpoint());

        Map<String, Object> parsed = (Map<String, Object>) JSON.deserializeUntyped(mock.lastRequest.getBody());
        List<Object> events = (List<Object>) parsed.get('events');
        System.assertEquals(1, events.size());
        Map<String, Object> evt = (Map<String, Object>) events[0];
        System.assertEquals(String.valueOf(a.Id), (String) evt.get('recordId'));
        System.assertEquals('UPSERT', (String) evt.get('changeType'));
        System.assertNotEquals(null, evt.get('record'));
    }

    @isTest
    static void deleteOnlyPathSkipsSoql() {
        Id fakeId = '0011x00000ABCDEAA1';
        StaticMock mock = new StaticMock(200, '{"ok":true}');
        Test.setMock(HttpCalloutMock.class, mock);

        Test.startTest();
        System.enqueueJob(new ApprovalSupabaseRelay(new Set<Id>(), new Set<Id>{ fakeId }));
        Test.stopTest();

        Map<String, Object> parsed = (Map<String, Object>) JSON.deserializeUntyped(mock.lastRequest.getBody());
        List<Object> events = (List<Object>) parsed.get('events');
        System.assertEquals(1, events.size());
        Map<String, Object> evt = (Map<String, Object>) events[0];
        System.assertEquals('DELETE', (String) evt.get('changeType'));
        System.assertEquals(null, evt.get('record'));
    }

    @isTest
    static void upsertIdMissingFromSoqlBecomesDelete() {
        Approval__c a = makeApproval();
        Id missingId = a.Id;
        delete a;
        StaticMock mock = new StaticMock(200, '{"ok":true}');
        Test.setMock(HttpCalloutMock.class, mock);

        Test.startTest();
        System.enqueueJob(new ApprovalSupabaseRelay(new Set<Id>{ missingId }, new Set<Id>()));
        Test.stopTest();

        Map<String, Object> parsed = (Map<String, Object>) JSON.deserializeUntyped(mock.lastRequest.getBody());
        List<Object> events = (List<Object>) parsed.get('events');
        Map<String, Object> evt = (Map<String, Object>) events[0];
        System.assertEquals('DELETE', (String) evt.get('changeType'),
            'a record present in upsertIds but missing from SOQL (deleted between publish and consume) should fall back to DELETE');
    }

    @isTest
    static void serverErrorReEnqueuesUntilMaxThenLogs() {
        Approval__c a = makeApproval();
        StaticMock mock = new StaticMock(500, '{"error":"boom"}');
        Test.setMock(HttpCalloutMock.class, mock);
        ApprovalSupabaseRelay.MAX_ATTEMPTS = 1;

        Test.startTest();
        System.enqueueJob(new ApprovalSupabaseRelay(new Set<Id>{ a.Id }, new Set<Id>()));
        Test.stopTest();

        List<Approval_Sync_Failure__c> failures = [
            SELECT Record_Id__c, Change_Type__c, Error__c, Attempt__c
              FROM Approval_Sync_Failure__c
        ];
        System.assertEquals(1, failures.size(), 'failure row should be logged at MAX_ATTEMPTS');
        System.assertEquals(String.valueOf(a.Id), failures[0].Record_Id__c);
        System.assertEquals('UPSERT', failures[0].Change_Type__c);
        System.assert(failures[0].Error__c.startsWith('HTTP 500'), 'should record server error: ' + failures[0].Error__c);
    }

    @isTest
    static void clientErrorDoesNotRetry() {
        Approval__c a = makeApproval();
        StaticMock mock = new StaticMock(400, '{"error":"bad"}');
        Test.setMock(HttpCalloutMock.class, mock);

        Test.startTest();
        System.enqueueJob(new ApprovalSupabaseRelay(new Set<Id>{ a.Id }, new Set<Id>()));
        Test.stopTest();

        List<Approval_Sync_Failure__c> failures = [SELECT Id, Error__c FROM Approval_Sync_Failure__c];
        System.assertEquals(1, failures.size(), '4xx should drop straight to failure log without retry');
        System.assert(failures[0].Error__c.startsWith('HTTP 400'));
    }

    @isTest
    static void emptyInputIsNoop() {
        StaticMock mock = new StaticMock(200, '{}');
        Test.setMock(HttpCalloutMock.class, mock);

        Test.startTest();
        System.enqueueJob(new ApprovalSupabaseRelay(new Set<Id>(), new Set<Id>()));
        Test.stopTest();

        System.assertEquals(null, mock.lastRequest, 'no callout should be made when both id sets are empty');
    }
}
