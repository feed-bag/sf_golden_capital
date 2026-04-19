public with sharing class OpportunityChecklistController {

    /**
     * Returns checklist items grouped by template for the given opportunity.
     */
    @AuraEnabled(cacheable=true)
    public static List<ChecklistGroup> getChecklistItems(Id opportunityId) {
        List<ChecklistGroup> groups = new List<ChecklistGroup>();

        // Get all templates that have items on this opportunity
        Map<Id, ChecklistGroup> groupMap = new Map<Id, ChecklistGroup>();

        List<Checklist__c> items = [
            SELECT Id, Name__c, Complete__c, Due_Date__c, Dealer_Visible__c,
                   Notes__c, LastModifiedDate,
                   Checklist_Template__c, Checklist_Template__r.Name,
                   Checklist_Template__r.Stage__c
            FROM Checklist__c
            WHERE Opportunity__c = :opportunityId
            ORDER BY Checklist_Template__c, CreatedDate ASC
        ];

        for (Checklist__c item : items) {
            Id templateId = item.Checklist_Template__c;

            if (!groupMap.containsKey(templateId)) {
                ChecklistGroup grp = new ChecklistGroup();
                grp.templateId = templateId;
                grp.templateName = item.Checklist_Template__r != null
                    ? item.Checklist_Template__r.Name
                    : 'General';
                grp.stage = item.Checklist_Template__r != null
                    ? item.Checklist_Template__r.Stage__c
                    : null;
                grp.items = new List<Checklist__c>();
                grp.totalCount = 0;
                grp.completeCount = 0;
                groupMap.put(templateId, grp);
            }

            ChecklistGroup grp = groupMap.get(templateId);
            grp.items.add(item);
            grp.totalCount++;
            if (item.Complete__c) {
                grp.completeCount++;
            }
        }

        // Also include ad-hoc items with no template
        List<Checklist__c> adHocItems = [
            SELECT Id, Name__c, Complete__c, Due_Date__c, Dealer_Visible__c,
                   Notes__c, LastModifiedDate, Checklist_Template__c
            FROM Checklist__c
            WHERE Opportunity__c = :opportunityId
            AND Checklist_Template__c = null
            ORDER BY CreatedDate ASC
        ];

        if (!adHocItems.isEmpty()) {
            ChecklistGroup adHocGroup = new ChecklistGroup();
            adHocGroup.templateId = null;
            adHocGroup.templateName = 'Ad Hoc';
            adHocGroup.stage = null;
            adHocGroup.items = adHocItems;
            adHocGroup.totalCount = adHocItems.size();
            adHocGroup.completeCount = 0;
            for (Checklist__c item : adHocItems) {
                if (item.Complete__c) adHocGroup.completeCount++;
            }
            groupMap.put(null, adHocGroup);
        }

        groups.addAll(groupMap.values());
        return groups;
    }

    /**
     * Toggle the Complete__c field on a checklist item.
     */
    @AuraEnabled
    public static void toggleComplete(Id itemId, Boolean complete) {
        Checklist__c item = new Checklist__c(
            Id = itemId,
            Complete__c = complete
        );
        update item;
    }

    /**
     * Add an ad-hoc checklist item to an opportunity.
     * templateId is optional — if provided, item is grouped under that template.
     */
    @AuraEnabled
    public static Checklist__c addItem(
        Id opportunityId,
        Id templateId,
        String name,
        Date dueDate,
        Boolean dealerVisible
    ) {
        Checklist__c item = new Checklist__c(
            Opportunity__c = opportunityId,
            Checklist_Template__c = templateId,
            Name__c = name,
            Due_Date__c = dueDate,
            Dealer_Visible__c = (dealerVisible != null ? dealerVisible : false),
            Complete__c = false
        );
        insert item;
        return item;
    }

    /**
     * Delete a checklist item.
     */
    @AuraEnabled
    public static void deleteItem(Id itemId) {
        delete new Checklist__c(Id = itemId);
    }

    /**
     * Save notes on a checklist item.
     */
    @AuraEnabled
    public static void saveNotes(Id itemId, String notes) {
        update new Checklist__c(Id = itemId, Notes__c = notes);
    }

    /**
     * Update the Dealer_Visible__c field on a checklist item.
     */
    @AuraEnabled
    public static void updateDealerVisible(Id itemId, Boolean dealerVisible) {
        update new Checklist__c(Id = itemId, Dealer_Visible__c = dealerVisible);
    }

    /**
     * Wrapper class grouping checklist items by template.
     */
    public class ChecklistGroup {
        @AuraEnabled public Id templateId;
        @AuraEnabled public String templateName;
        @AuraEnabled public String stage;
        @AuraEnabled public List<Checklist__c> items;
        @AuraEnabled public Integer totalCount;
        @AuraEnabled public Integer completeCount;
    }
}
