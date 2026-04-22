@isTest
private class OpportunityDashboardControllerTest {

    @TestSetup
    static void setup() {
        Account acct = new Account(Name = 'Test Account');
        insert acct;

        List<Opportunity> opps = new List<Opportunity>{
            new Opportunity(Name = 'Opp A', AccountId = acct.Id, StageName = 'Prospecting', CloseDate = Date.today().addDays(30), Amount = 10000),
            new Opportunity(Name = 'Opp B', AccountId = acct.Id, StageName = 'Qualification', CloseDate = Date.today().addDays(60), Amount = 20000),
            new Opportunity(Name = 'Opp C', AccountId = acct.Id, StageName = 'Prospecting', CloseDate = Date.today().addDays(90), Amount = 5000)
        };
        insert opps;
    }

    @isTest
    static void testGetOpenOpportunities() {
        List<Opportunity> result = OpportunityDashboardController.getOpenOpportunities();
        System.assert(result.size() >= 3, 'Expected at least 3 open opportunities');
    }

    @isTest
    static void testGetPipelineStats() {
        OpportunityDashboardController.PipelineStats stats = OpportunityDashboardController.getPipelineStats();
        System.assert(stats.activeDeals >= 3, 'Expected active deals');
        System.assertNotEquals(null, stats.volumeFundedThisMonth);
    }

    @isTest
    static void testGetOpportunitiesForList() {
        List<Opportunity> result = OpportunityDashboardController.getOpportunitiesForList();
        System.assert(result.size() >= 3, 'Expected at least 3 opportunities');
    }

    @isTest
    static void testGetActiveUsers() {
        List<User> users = OpportunityDashboardController.getActiveUsers();
        System.assert(users.size() > 0, 'Expected at least one active user');
    }

    @isTest
    static void testUpdateOpportunityStage() {
        Account acct = [SELECT Id FROM Account WHERE Name = 'Test Account' LIMIT 1];
        Opportunity opp = new Opportunity(Name = 'Stage Test', AccountId = acct.Id, StageName = 'Prospecting', CloseDate = Date.today().addDays(30));
        insert opp;
        OpportunityDashboardController.updateOpportunityStage(opp.Id, 'Qualification');
        Opportunity updated = [SELECT StageName FROM Opportunity WHERE Id = :opp.Id];
        System.assertEquals('Qualification', updated.StageName);
    }

    @isTest
    static void testBulkUpdateStage() {
        List<Opportunity> opps = [SELECT Id FROM Opportunity WHERE StageName = 'Prospecting'];
        List<Id> ids = new List<Id>();
        for (Opportunity o : opps) ids.add(o.Id);

        OpportunityDashboardController.bulkUpdateStage(ids, 'Needs Analysis');

        List<Opportunity> updated = [SELECT StageName FROM Opportunity WHERE Id IN :ids];
        for (Opportunity o : updated) {
            System.assertEquals('Needs Analysis', o.StageName);
        }
    }

    @isTest
    static void testBulkUpdateOwner() {
        List<Opportunity> opps = [SELECT Id FROM Opportunity LIMIT 2];
        List<Id> ids = new List<Id>();
        for (Opportunity o : opps) ids.add(o.Id);

        User currentUser = [SELECT Id FROM User WHERE Id = :UserInfo.getUserId()];
        OpportunityDashboardController.bulkUpdateOwner(ids, currentUser.Id);

        List<Opportunity> updated = [SELECT OwnerId FROM Opportunity WHERE Id IN :ids];
        for (Opportunity o : updated) {
            System.assertEquals(currentUser.Id, o.OwnerId);
        }
    }

    @isTest
    static void testBulkDeleteOpportunities() {
        List<Opportunity> opps = [SELECT Id FROM Opportunity WHERE Name = 'Opp C'];
        List<Id> ids = new List<Id>();
        for (Opportunity o : opps) ids.add(o.Id);

        OpportunityDashboardController.bulkDeleteOpportunities(ids);

        Integer remaining = [SELECT COUNT() FROM Opportunity WHERE Id IN :ids];
        System.assertEquals(0, remaining);
    }

    @isTest
    static void testColumnPreferenceInsertAndRetrieve() {
        String json = '["accountName","StageName","Amount"]';

        Test.startTest();
        OpportunityDashboardController.saveColumnPreference(json);
        String retrieved = OpportunityDashboardController.getColumnPreference();
        Test.stopTest();

        System.assertEquals(json, retrieved, 'Saved preference should match retrieved value');
    }

    @isTest
    static void testColumnPreferenceUpdate() {
        String first  = '["accountName","StageName"]';
        String second = '["accountName","StageName","Amount","Type"]';

        Test.startTest();
        OpportunityDashboardController.saveColumnPreference(first);
        OpportunityDashboardController.saveColumnPreference(second);
        String retrieved = OpportunityDashboardController.getColumnPreference();
        Test.stopTest();

        System.assertEquals(second, retrieved, 'Second save should overwrite first');
    }

    @isTest
    static void testColumnPreferenceNullWhenNotSet() {
        // No List_Column_Pref__c inserted — should return null
        Test.startTest();
        String result = OpportunityDashboardController.getColumnPreference();
        Test.stopTest();

        System.assertEquals(null, result, 'Should return null when no preference is saved');
    }
}