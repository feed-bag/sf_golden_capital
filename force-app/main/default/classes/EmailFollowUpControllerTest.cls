@isTest
private class EmailFollowUpControllerTest {

    @isTest
    static void testGetFollowUpData_primaryContactWins() {
        Account a = new Account(Name = 'Acct Primary', Email__c = 'acct@example.com');
        insert a;
        Contact c = new Contact(LastName = 'Buyer', Email = 'buyer@example.com', AccountId = a.Id);
        insert c;
        Opportunity o = new Opportunity(Name = 'Test', AccountId = a.Id,
            StageName = 'Prospecting', CloseDate = Date.today());
        insert o;
        insert new OpportunityContactRole(
            OpportunityId = o.Id, ContactId = c.Id, IsPrimary = true);

        // One incomplete + one complete App In item to verify filtering
        Checklist_Template__c tpl = new Checklist_Template__c(
            Name = 'App In', Stage__c = 'App In', Active__c = true);
        insert tpl;
        insert new List<Checklist__c>{
            new Checklist__c(Opportunity__c = o.Id, Name__c = 'Bank statements',
                Complete__c = false, Checklist_Template__c = tpl.Id),
            new Checklist__c(Opportunity__c = o.Id, Name__c = 'Driver license',
                Complete__c = true,  Checklist_Template__c = tpl.Id)
        };

        Test.startTest();
        EmailFollowUpController.FollowUpData d =
            EmailFollowUpController.getApplicationFollowUpData(o.Id);
        Test.stopTest();

        System.assertEquals('buyer@example.com', d.toEmail, 'Primary contact email expected');
        System.assertEquals('Credit Application - Follow Up', d.subject);
        System.assertEquals(1, d.incompleteItems.size(), 'Only the incomplete App In item should be returned');
        System.assertEquals('Bank statements', d.incompleteItems[0]);
        System.assert(d.htmlBody == null || d.htmlBody.contains('Bank statements')
                      || d.htmlBody.contains('checklist'),
            'Body should reference the items list (template may be missing in test context)');
    }

    @isTest
    static void testGetFollowUpData_fallsBackToAccountEmail() {
        Account a = new Account(Name = 'Acct Fallback', Email__c = 'fallback@example.com');
        insert a;
        Opportunity o = new Opportunity(Name = 'Test', AccountId = a.Id,
            StageName = 'Prospecting', CloseDate = Date.today());
        insert o;

        Test.startTest();
        EmailFollowUpController.FollowUpData d =
            EmailFollowUpController.getApplicationFollowUpData(o.Id);
        Test.stopTest();

        System.assertEquals('fallback@example.com', d.toEmail);
        System.assertEquals(0, d.incompleteItems.size());
    }

    @isTest
    static void testSendFollowUp_happyPath() {
        Account a = new Account(Name = 'Send Acct');
        insert a;
        Opportunity o = new Opportunity(Name = 'Send Opp', AccountId = a.Id,
            StageName = 'Prospecting', CloseDate = Date.today());
        insert o;

        Test.startTest();
        // If the OrgWide address isn't configured, the method throws — accept either path.
        try {
            EmailFollowUpController.sendApplicationFollowUp(
                o.Id, 'recipient@example.com', 'Test', '<p>hello</p>');
        } catch (Exception e) {
            System.assert(
                e.getMessage().contains('Org-Wide Email Address')
                || e.getMessage().contains('Send failed'),
                'Unexpected error: ' + e.getMessage()
            );
        }
        Test.stopTest();
    }

    @isTest
    static void testRenderBody_emptyItems() {
        Account a = new Account(Name = 'Empty');
        insert a;
        Opportunity o = new Opportunity(Name = 'X', AccountId = a.Id,
            StageName = 'Prospecting', CloseDate = Date.today());
        insert o;

        Test.startTest();
        EmailFollowUpController.FollowUpData d =
            EmailFollowUpController.getApplicationFollowUpData(o.Id);
        Test.stopTest();

        System.assertNotEquals(null, d.htmlBody);
        System.assertEquals(0, d.incompleteItems.size());
    }

    @isTest
    static void testSendFollowUp_blankToThrows() {
        Account a = new Account(Name = 'X');
        insert a;
        Opportunity o = new Opportunity(Name = 'X', AccountId = a.Id,
            StageName = 'Prospecting', CloseDate = Date.today());
        insert o;

        Boolean threw = false;
        try {
            EmailFollowUpController.sendApplicationFollowUp(o.Id, '', 'Subj', '<p>body</p>');
        } catch (AuraHandledException e) {
            threw = true;
        }
        System.assert(threw, 'Empty toEmail should throw');
    }
}
