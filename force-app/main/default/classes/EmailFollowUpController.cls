public with sharing class EmailFollowUpController {

    private static final String ORG_WIDE_ADDRESS = 'credit@golden-cap.com';
    private static final String SUBJECT          = 'Credit Application - Follow Up';
    private static final String STAGE_FILTER     = 'App In';
    private static final String STATIC_RESOURCE  = 'applicationFollowUpBody';
    private static final String ITEMS_PLACEHOLDER = '[[INCOMPLETE_ITEMS]]';

    @AuraEnabled(cacheable=true)
    public static FollowUpData getApplicationFollowUpData(Id oppId) {
        FollowUpData out = new FollowUpData();

        Opportunity opp = [
            SELECT Id, Name, AccountId, Account.Name, Account.Email__c
            FROM Opportunity
            WHERE Id = :oppId
            LIMIT 1
        ];

        // Primary contact via standard OpportunityContactRole; fall back to Account.Email__c.
        List<OpportunityContactRole> primary = [
            SELECT ContactId, Contact.Name, Contact.Email
            FROM OpportunityContactRole
            WHERE OpportunityId = :oppId AND IsPrimary = true AND Contact.Email != null
            LIMIT 1
        ];
        if (!primary.isEmpty()) {
            out.toName  = primary[0].Contact.Name;
            out.toEmail = primary[0].Contact.Email;
            out.toSource = 'Primary contact role';
        } else if (opp.AccountId != null && String.isNotBlank(opp.Account.Email__c)) {
            out.toName  = opp.Account.Name;
            out.toEmail = opp.Account.Email__c;
            out.toSource = 'Account email (no primary contact)';
        } else {
            out.toName  = '';
            out.toEmail = '';
            out.toSource = 'No recipient found — please enter manually';
        }

        // Incomplete App In checklist items.
        List<Checklist__c> items = [
            SELECT Name__c
            FROM Checklist__c
            WHERE Opportunity__c = :oppId
              AND Complete__c = false
              AND Checklist_Template__r.Stage__c = :STAGE_FILTER
            ORDER BY Name__c
        ];
        List<String> labels = new List<String>();
        for (Checklist__c c : items) {
            if (String.isNotBlank(c.Name__c)) labels.add(c.Name__c);
        }
        out.incompleteItems = labels;

        out.subject  = SUBJECT;
        out.htmlBody = renderBody(labels);

        OrgWideEmailAddress[] owe = [
            SELECT Id FROM OrgWideEmailAddress WHERE Address = :ORG_WIDE_ADDRESS LIMIT 1
        ];
        out.orgWideEmailAddressId = owe.isEmpty() ? null : owe[0].Id;
        out.fromAddress = ORG_WIDE_ADDRESS;

        return out;
    }

    @AuraEnabled
    public static void sendApplicationFollowUp(
        Id oppId, String toEmail, String subject, String htmlBody
    ) {
        if (String.isBlank(toEmail)) {
            throw new AuraHandledException('A recipient email address is required.');
        }
        OrgWideEmailAddress[] owe = [
            SELECT Id FROM OrgWideEmailAddress WHERE Address = :ORG_WIDE_ADDRESS LIMIT 1
        ];
        if (owe.isEmpty()) {
            throw new AuraHandledException(
                'Org-Wide Email Address ' + ORG_WIDE_ADDRESS + ' is not configured or not verified yet.'
            );
        }

        // Editor passes a body fragment; wrap it in a minimal HTML envelope for email clients.
        String wrappedBody = '<html><head><meta http-equiv="Content-Type" content="text/html; charset=utf-8"></head><body>'
                           + htmlBody + '</body></html>';
        Messaging.SingleEmailMessage msg = new Messaging.SingleEmailMessage();
        msg.setToAddresses(new List<String>{ toEmail });
        msg.setSubject(subject);
        msg.setHtmlBody(wrappedBody);
        msg.setOrgWideEmailAddressId(owe[0].Id);
        msg.setWhatId(oppId);
        msg.setSaveAsActivity(true);
        msg.setUseSignature(false);

        Messaging.SendEmailResult[] results = Messaging.sendEmail(
            new List<Messaging.SingleEmailMessage>{ msg }, false
        );
        if (!results[0].isSuccess()) {
            throw new AuraHandledException('Send failed: ' + results[0].getErrors()[0].getMessage());
        }
    }

    // Loads the HTML template static resource and splices in the dynamic bullets.
    private static String renderBody(List<String> incompleteItems) {
        StaticResource[] sr = [SELECT Body FROM StaticResource WHERE Name = :STATIC_RESOURCE LIMIT 1];
        if (sr.isEmpty()) return buildItemsList(incompleteItems);
        String html = sr[0].Body.toString();
        return html.replace(ITEMS_PLACEHOLDER, buildItemsList(incompleteItems));
    }

    private static String buildItemsList(List<String> items) {
        if (items == null || items.isEmpty()) {
            return '<div style="font-family: Aptos, Arial, Helvetica, sans-serif; font-size: 12pt; color: rgb(0,0,0);">'
                 + '<i>All App In checklist items are complete — please confirm whether anything else is outstanding on your end.</i>'
                 + '</div>';
        }
        String listStyle = 'text-align:left; margin-top:0px; margin-bottom:0px;';
        String itemStyle = 'font-family: Aptos, Arial, Helvetica, sans-serif; font-size: 12pt; color: rgb(0,0,0); list-style-type: "- ";';
        String html = '<ul style="' + listStyle + '">';
        for (String label : items) {
            html += '<li style="' + itemStyle + '"><div dir="ltr" role="presentation"><i>'
                 + label.escapeHtml4() + '</i></div></li>';
        }
        html += '</ul>';
        return html;
    }

    public class FollowUpData {
        @AuraEnabled public String toName;
        @AuraEnabled public String toEmail;
        @AuraEnabled public String toSource;
        @AuraEnabled public String fromAddress;
        @AuraEnabled public Id     orgWideEmailAddressId;
        @AuraEnabled public String subject;
        @AuraEnabled public String htmlBody;
        @AuraEnabled public List<String> incompleteItems;
    }
}
