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
        System.assert(m.opportunitiesByMonth.size() >= 4 && m.opportunitiesByMonth.size() <= 5,
            'MONTH should produce 4–5 weekly buckets for the calendar month');
        System.assert(m.volumeFundedByMonth.size() >= 4 && m.volumeFundedByMonth.size() <= 5,
            'MONTH should produce 4–5 weekly buckets for the calendar month');
        System.assertNotEquals(null, m.pipelineByStage, 'Pipeline-by-stage list should be present');
    }

    @isTest
    static void testSeriesGranularityScalesWithRange() {
        Account acct = [SELECT Id FROM Account WHERE Name = 'Test Account' LIMIT 1];
        insert new Opportunity(Name = 'Series Funded', AccountId = acct.Id,
            StageName = 'Prospecting', CloseDate = Date.today(),
            Amount = 1000, Funded_Date__c = Date.today());

        Test.startTest();
        OpportunityDashboardController.DashboardMetrics week =
            OpportunityDashboardController.getDashboardMetrics('WEEK', null);
        OpportunityDashboardController.DashboardMetrics month =
            OpportunityDashboardController.getDashboardMetrics('MONTH', null);
        OpportunityDashboardController.DashboardMetrics quarter =
            OpportunityDashboardController.getDashboardMetrics('QUARTER', null);
        OpportunityDashboardController.DashboardMetrics year =
            OpportunityDashboardController.getDashboardMetrics('YEAR', null);
        Test.stopTest();

        // WEEK → 7 daily buckets
        System.assertEquals(7, week.opportunitiesByMonth.size(), 'WEEK should produce 7 daily buckets');
        System.assertEquals(7, week.volumeFundedByMonth.size());
        // MONTH → 4–5 weekly buckets
        System.assert(month.opportunitiesByMonth.size() >= 4 && month.opportunitiesByMonth.size() <= 5,
            'MONTH should produce 4–5 weekly buckets');
        // QUARTER → 3 monthly buckets
        System.assertEquals(3, quarter.opportunitiesByMonth.size(), 'QUARTER should produce 3 monthly buckets');
        // YEAR → 12 monthly buckets
        System.assertEquals(12, year.opportunitiesByMonth.size(), 'YEAR should produce 12 monthly buckets');
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
    static void testPaceConversionKpis() {
        Account acct = [SELECT Id FROM Account WHERE Name = 'Test Account' LIMIT 1];
        Date today = Date.today();
        // One created-this-month opp that gets funded + approved this month.
        Opportunity oppNew = new Opportunity(Name = 'Pace New', AccountId = acct.Id,
            StageName = 'Prospecting', CloseDate = today, Amount = 10000,
            Funded_Date__c = today);
        // One created last month, funded this month — counts toward pace numerator
        // but NOT denominator (denominator = created this month).
        Opportunity oppOld = new Opportunity(Name = 'Pace Old', AccountId = acct.Id,
            StageName = 'Prospecting', CloseDate = today, Amount = 5000,
            Funded_Date__c = today);
        insert new List<Opportunity>{ oppNew, oppOld };

        // Approval child for the new opp marks "approved this period"
        Id lenderRtId = Schema.SObjectType.Account
            .getRecordTypeInfosByDeveloperName().get('Lender_Account').getRecordTypeId();
        Account lender = new Account(Name = 'Test Lender', RecordTypeId = lenderRtId);
        insert lender;
        insert new Approval__c(
            Opportunity__c = oppNew.Id,
            Purchase_Price__c = 10000,
            Net_Funded_Amount__c = 10000,
            Contract_Type__c = 'EFA',
            Funding_Source__c = lender.Id
        );

        Test.startTest();
        OpportunityDashboardController.DashboardMetrics m =
            OpportunityDashboardController.getDashboardMetrics('MONTH', null);
        List<Opportunity> approvedDrill =
            OpportunityDashboardController.getOpportunitiesForKpi('approved', 'MONTH', null);
        List<Opportunity> fundedDrill =
            OpportunityDashboardController.getOpportunitiesForKpi('funded', 'MONTH', null);
        Test.stopTest();

        System.assert(m.kpis.cohortApproved >= 1, 'Pace approved should count opps with Approval child this period');
        System.assert(m.kpis.cohortFunded   >= 2, 'Pace funded should count both funded-in-period opps regardless of created date');
        System.assert(approvedDrill.size() >= 1, 'approved drill should return opps with Approval in period');
        System.assert(fundedDrill.size()   >= 2, 'funded drill should return both funded-in-period opps');
    }

    @isTest
    static void testAnnualGoalBlock() {
        Account acct = [SELECT Id FROM Account WHERE Name = 'Test Account' LIMIT 1];
        insert new Opportunity(Name = 'Goal Funded', AccountId = acct.Id,
            StageName = 'Prospecting', CloseDate = Date.today(),
            Amount = 250000, Funded_Date__c = Date.today());

        Test.startTest();
        OpportunityDashboardController.DashboardMetrics m =
            OpportunityDashboardController.getDashboardMetrics('MONTH', null);
        Test.stopTest();

        System.assertNotEquals(null, m.annualGoal, 'Annual goal block should be populated');
        System.assertEquals(10000000, m.annualGoal.goal);
        System.assert(m.annualGoal.actual >= 250000, 'Should include current-year funded amount');
        System.assert(m.annualGoal.daysInYear == 365 || m.annualGoal.daysInYear == 366, 'daysInYear should reflect calendar year');
        System.assert(m.annualGoal.daysElapsed >= 1 && m.annualGoal.daysElapsed <= m.annualGoal.daysInYear);
        System.assert(m.annualGoal.expectedToDate >= 0 && m.annualGoal.expectedToDate <= m.annualGoal.goal);
        System.assertEquals(false, m.annualGoal.ownerScoped, 'No owner filter → not owner-scoped');
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