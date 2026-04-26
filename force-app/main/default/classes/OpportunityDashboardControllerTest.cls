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

    @isTest
    static void testGetDealersForOpportunity() {
        Account acct = [SELECT Id FROM Account WHERE Name = 'Test Account' LIMIT 1];
        List<Account> dealers = new List<Account>{
            new Account(Name = 'Dealer Alpha'),
            new Account(Name = 'Dealer Bravo')
        };
        insert dealers;

        Opportunity opp = new Opportunity(
            Name = 'Dealer Test', AccountId = acct.Id,
            StageName = 'Prospecting', CloseDate = Date.today().addDays(30)
        );
        insert opp;

        insert new List<Equipment__c>{
            new Equipment__c(Opportunity__c = opp.Id, Dealer__c = dealers[0].Id),
            new Equipment__c(Opportunity__c = opp.Id, Dealer__c = dealers[1].Id),
            new Equipment__c(Opportunity__c = opp.Id, Dealer__c = dealers[0].Id)
        };

        List<Map<String, Object>> result = OpportunityDashboardController.getDealersForOpportunity(opp.Id);
        System.assertEquals(2, result.size(), 'Two distinct dealers expected from three equipment rows');
        System.assertEquals('Dealer Alpha', String.valueOf(result[0].get('name')), 'Sorted by name asc');
        System.assertEquals('Dealer Bravo', String.valueOf(result[1].get('name')));
    }

    @isTest
    static void testGetDashboardMetricsMonthAllOwners() {
        Account acct = [SELECT Id FROM Account WHERE Name = 'Test Account' LIMIT 1];
        Date today = Date.today();
        // Funded this month + funded last month for delta math
        Opportunity oppCur = new Opportunity(
            Name = 'Funded This Month', AccountId = acct.Id,
            StageName = 'Prospecting', CloseDate = today,
            Amount = 50000, Funded_Date__c = today
        );
        Opportunity oppPrev = new Opportunity(
            Name = 'Funded Last Month', AccountId = acct.Id,
            StageName = 'Prospecting', CloseDate = today.addMonths(-1),
            Amount = 25000, Funded_Date__c = today.addMonths(-1)
        );
        insert new List<Opportunity>{ oppCur, oppPrev };

        Test.startTest();
        OpportunityDashboardController.DashboardMetrics m =
            OpportunityDashboardController.getDashboardMetrics('MONTH', null);
        Test.stopTest();

        System.assertEquals('This Month', m.period.label);
        System.assert(m.kpis.volumeFunded >= 50000, 'Current-month funded volume should include test record');
        System.assert(m.kpis.volumeFundedPrev >= 25000, 'Previous-month funded volume should include prior-month test record');
        System.assert(m.kpis.dealsFunded >= 1);
        System.assert(m.kpis.newOpportunities >= 1, 'Current-month created should include the new opps');
        System.assertEquals(12, m.opportunitiesByMonth.size(), '12-month timeline expected');
        System.assertEquals(12, m.volumeFundedByMonth.size(), '12-month timeline expected');
        System.assertNotEquals(null, m.pipelineByStage, 'Pipeline-by-stage list should be present');
    }

    @isTest
    static void testGetDashboardMetricsOwnerFilteredAcrossRanges() {
        Account acct = [SELECT Id FROM Account WHERE Name = 'Test Account' LIMIT 1];
        Id me = UserInfo.getUserId();
        Opportunity opp = new Opportunity(
            Name = 'Owner Filtered', AccountId = acct.Id,
            StageName = 'Prospecting', CloseDate = Date.today(),
            Amount = 75000, Funded_Date__c = Date.today(), OwnerId = me
        );
        insert opp;

        Test.startTest();
        OpportunityDashboardController.DashboardMetrics week =
            OpportunityDashboardController.getDashboardMetrics('WEEK', me);
        OpportunityDashboardController.DashboardMetrics quarter =
            OpportunityDashboardController.getDashboardMetrics('QUARTER', me);
        OpportunityDashboardController.DashboardMetrics year =
            OpportunityDashboardController.getDashboardMetrics('YEAR', me);
        Test.stopTest();

        System.assertEquals('This Week', week.period.label);
        System.assertEquals('This Quarter', quarter.period.label);
        System.assertEquals('This Year', year.period.label);
        // Owner-filtered → topOwners is intentionally empty (single-row table is noise)
        System.assertEquals(0, week.topOwners.size(), 'Owner-filtered topOwners should be empty');
        System.assert(year.kpis.volumeFunded >= 75000, 'Owner-filtered year should include test opp');
    }

    @isTest
    static void testCohortConversionKpis() {
        Account acct = [SELECT Id FROM Account WHERE Name = 'Test Account' LIMIT 1];
        Date today = Date.today();
        // Three opps created this month: 1 approved + funded, 1 only approved, 1 neither.
        insert new List<Opportunity>{
            new Opportunity(Name = 'Cohort Funded', AccountId = acct.Id,
                StageName = 'Prospecting', CloseDate = today, Amount = 10000,
                Has_Been_Approved__c = true, Funded_Date__c = today),
            new Opportunity(Name = 'Cohort Approved', AccountId = acct.Id,
                StageName = 'Prospecting', CloseDate = today, Amount = 5000,
                Has_Been_Approved__c = true),
            new Opportunity(Name = 'Cohort None', AccountId = acct.Id,
                StageName = 'Prospecting', CloseDate = today, Amount = 2500)
        };

        Test.startTest();
        OpportunityDashboardController.DashboardMetrics m =
            OpportunityDashboardController.getDashboardMetrics('MONTH', null);
        List<Opportunity> approvedDrill =
            OpportunityDashboardController.getOpportunitiesForKpi('approved', 'MONTH', null);
        List<Opportunity> fundedDrill =
            OpportunityDashboardController.getOpportunitiesForKpi('funded', 'MONTH', null);
        Test.stopTest();

        System.assert(m.kpis.cohortApproved >= 2, 'Should count both approved cohort members');
        System.assert(m.kpis.cohortFunded   >= 1, 'Should count the funded cohort member');
        System.assert(approvedDrill.size() >= 2, 'approved drill should return cohort members');
        System.assert(fundedDrill.size()   >= 1, 'funded drill should return cohort members');
    }

    @isTest
    static void testGetOpportunitiesForKpi() {
        Account acct = [SELECT Id FROM Account WHERE Name = 'Test Account' LIMIT 1];
        insert new Opportunity(
            Name = 'Drill Funded', AccountId = acct.Id,
            StageName = 'Prospecting', CloseDate = Date.today(),
            Amount = 12345, Funded_Date__c = Date.today()
        );

        Test.startTest();
        List<Opportunity> volumeRows  = OpportunityDashboardController.getOpportunitiesForKpi('volume',   'MONTH', null);
        List<Opportunity> newRows     = OpportunityDashboardController.getOpportunitiesForKpi('new',      'MONTH', null);
        List<Opportunity> pipelineRows= OpportunityDashboardController.getOpportunitiesForKpi('pipeline', 'MONTH', null);
        Test.stopTest();

        System.assert(volumeRows.size()  >= 1, 'volume KPI should return funded opps in window');
        System.assert(newRows.size()     >= 1, 'new KPI should return opps created in window');
        System.assert(pipelineRows.size() >= 1, 'pipeline KPI should return open opps');
    }

    @isTest
    static void testGetDealersForOpportunityNoEquipment() {
        Account acct = [SELECT Id FROM Account WHERE Name = 'Test Account' LIMIT 1];
        Opportunity opp = new Opportunity(
            Name = 'No Equip', AccountId = acct.Id,
            StageName = 'Prospecting', CloseDate = Date.today().addDays(30)
        );
        insert opp;

        List<Map<String, Object>> result = OpportunityDashboardController.getDealersForOpportunity(opp.Id);
        System.assertEquals(0, result.size(), 'Empty list expected when no equipment exists');
    }
}