@isTest
private class ApprovalChangeTriggerTest {

    private class NoopMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);
            res.setBody('{}');
            return res;
        }
    }

    @isTest
    static void testInsertUpdateDelete() {
        Id lenderRtId = Schema.SObjectType.Account.getRecordTypeInfosByName().get('Lender Account').getRecordTypeId();
        Account funder = new Account(Name = 'Test Funder', RecordTypeId = lenderRtId);
        insert funder;

        Opportunity opp = new Opportunity(
            Name = 'Test Opp',
            StageName = 'Prospecting',
            CloseDate = Date.today().addDays(30)
        );
        insert opp;

        Test.setMock(HttpCalloutMock.class, new NoopMock());

        Test.startTest();

        Approval__c approval = new Approval__c(
            Opportunity__c = opp.Id,
            Purchase_Price__c = 10000,
            Net_Funded_Amount__c = 9000,
            Contract_Type__c = 'True Lease',
            Funding_Source__c = funder.Id
        );
        insert approval;

        approval.Status__c = 'Terms Accepted';
        update approval;

        delete approval;

        Test.stopTest();
    }
}
