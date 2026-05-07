trigger ApprovalChangeEventTrigger on Approval_Change__e (after insert) {
    Set<Id> upsertIds = new Set<Id>();
    Set<Id> deleteIds = new Set<Id>();

    for (Approval_Change__e e : Trigger.new) {
        if (String.isBlank(e.Record_Id__c)) continue;
        Id recId;
        try {
            recId = Id.valueOf(e.Record_Id__c);
        } catch (Exception ex) {
            continue;
        }
        if (e.Change_Type__c == 'DELETE') {
            deleteIds.add(recId);
        } else {
            upsertIds.add(recId);
        }
    }

    if (!upsertIds.isEmpty() || !deleteIds.isEmpty()) {
        System.enqueueJob(new ApprovalSupabaseRelay(upsertIds, deleteIds));
    }
}
