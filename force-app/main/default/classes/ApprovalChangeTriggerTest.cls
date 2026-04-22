@isTest
private class ApprovalChangeTriggerTest {

    @isTest
    static void testInsertUpdateDelete() {
        Opportunity opp = new Opportunity(
            Name = 'Test Opp',
            StageName = 'Prospecting',
            CloseDate = Date.today().addDays(30)
        );
        insert opp;

        Test.startTest();

        Approval__c approval = new Approval__c(
            Opportunity__c = opp.Id,
            Purchase_Price__c = 10000,
            Net_Funded_Amount__c = 9000,
            Contract_Type__c = 'Lease',
            Funding_Source__c = 'Test Funder'
        );
        insert approval;

        approval.Status__c = 'Approved';
        update approval;

        delete approval;

        Test.stopTest();
    }
}
