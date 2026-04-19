@isTest
private class OpportunityChecklistControllerTest {

    @TestSetup
    static void makeData() {
        Account acc = new Account(Name = 'Test Account');
        insert acc;

        Opportunity opp = new Opportunity(
            Name = 'Test Opp',
            AccountId = acc.Id,
            StageName = 'App In',
            CloseDate = Date.today().addDays(30)
        );
        insert opp;

        Checklist_Template__c template = new Checklist_Template__c(
            Name = 'App In',
            Stage__c = 'App In',
            Active__c = true
        );
        insert template;

        List<Checklist__c> items = new List<Checklist__c>{
            new Checklist__c(
                Name__c = 'Item One',
                Opportunity__c = opp.Id,
                Checklist_Template__c = template.Id,
                Complete__c = false,
                Dealer_Visible__c = false
            ),
            new Checklist__c(
                Name__c = 'Item Two',
                Opportunity__c = opp.Id,
                Checklist_Template__c = template.Id,
                Complete__c = true,
                Dealer_Visible__c = true
            )
        };
        insert items;
    }

    @isTest
    static void testGetChecklistItems() {
        Opportunity opp = [SELECT Id FROM Opportunity LIMIT 1];

        Test.startTest();
        List<OpportunityChecklistController.ChecklistGroup> groups =
            OpportunityChecklistController.getChecklistItems(opp.Id);
        Test.stopTest();

        System.assertEquals(1, groups.size(), 'Should return one group');
        System.assertEquals(2, groups[0].totalCount, 'Total count should be 2');
        System.assertEquals(1, groups[0].completeCount, 'Complete count should be 1');
        System.assertEquals('App In', groups[0].templateName);
    }

    @isTest
    static void testToggleComplete() {
        Checklist__c item = [SELECT Id, Complete__c FROM Checklist__c WHERE Name__c = 'Item One' LIMIT 1];
        System.assertEquals(false, item.Complete__c);

        Test.startTest();
        OpportunityChecklistController.toggleComplete(item.Id, true);
        Test.stopTest();

        item = [SELECT Complete__c FROM Checklist__c WHERE Id = :item.Id];
        System.assertEquals(true, item.Complete__c);
    }

    @isTest
    static void testAddItem() {
        Opportunity opp = [SELECT Id FROM Opportunity LIMIT 1];
        Checklist_Template__c template = [SELECT Id FROM Checklist_Template__c LIMIT 1];

        Test.startTest();
        Checklist__c newItem = OpportunityChecklistController.addItem(
            opp.Id,
            template.Id,
            'Ad Hoc Item',
            Date.today(),
            true
        );
        Test.stopTest();

        System.assertNotEquals(null, newItem.Id);
        Checklist__c saved = [SELECT Name__c, Dealer_Visible__c FROM Checklist__c WHERE Id = :newItem.Id];
        System.assertEquals('Ad Hoc Item', saved.Name__c);
        System.assertEquals(true, saved.Dealer_Visible__c);
    }

    @isTest
    static void testAddItemNoTemplate() {
        Opportunity opp = [SELECT Id FROM Opportunity LIMIT 1];

        Test.startTest();
        Checklist__c newItem = OpportunityChecklistController.addItem(
            opp.Id, null, 'No Template Item', null, false
        );
        Test.stopTest();

        System.assertNotEquals(null, newItem.Id);
    }

    @isTest
    static void testDeleteItem() {
        Checklist__c item = [SELECT Id FROM Checklist__c WHERE Name__c = 'Item One' LIMIT 1];

        Test.startTest();
        OpportunityChecklistController.deleteItem(item.Id);
        Test.stopTest();

        List<Checklist__c> remaining = [SELECT Id FROM Checklist__c WHERE Id = :item.Id];
        System.assertEquals(0, remaining.size(), 'Item should be deleted');
    }

    @isTest
    static void testUpdateDealerVisible() {
        Checklist__c item = [SELECT Id, Dealer_Visible__c FROM Checklist__c WHERE Name__c = 'Item One' LIMIT 1];
        Test.startTest();
        OpportunityChecklistController.updateDealerVisible(item.Id, true);
        Test.stopTest();
        item = [SELECT Dealer_Visible__c FROM Checklist__c WHERE Id = :item.Id];
        System.assertEquals(true, item.Dealer_Visible__c);
    }

    @isTest
    static void testUpdateDealerCleared() {
        Checklist__c item = [SELECT Id, Dealer_Cleared__c FROM Checklist__c WHERE Name__c = 'Item One' LIMIT 1];
        Test.startTest();
        OpportunityChecklistController.updateDealerCleared(item.Id, true);
        Test.stopTest();
        item = [SELECT Dealer_Cleared__c FROM Checklist__c WHERE Id = :item.Id];
        System.assertEquals(true, item.Dealer_Cleared__c);
    }

    @isTest
    static void testSaveNotes() {
        Checklist__c item = [SELECT Id FROM Checklist__c WHERE Name__c = 'Item One' LIMIT 1];
        Test.startTest();
        OpportunityChecklistController.saveNotes(item.Id, 'Test note');
        Test.stopTest();
        item = [SELECT Notes__c FROM Checklist__c WHERE Id = :item.Id];
        System.assertEquals('Test note', item.Notes__c);
    }

    @isTest
    static void testGetChecklistItemsAdHoc() {
        Opportunity opp = [SELECT Id FROM Opportunity LIMIT 1];

        // Add an ad-hoc item with no template
        insert new Checklist__c(
            Name__c = 'Ad Hoc',
            Opportunity__c = opp.Id,
            Complete__c = false
        );

        Test.startTest();
        List<OpportunityChecklistController.ChecklistGroup> groups =
            OpportunityChecklistController.getChecklistItems(opp.Id);
        Test.stopTest();

        // Should now have 2 groups: the template group + ad hoc
        System.assertEquals(2, groups.size(), 'Should return two groups (template + ad hoc)');
    }
}
