trigger ApprovalChangeTrigger on Approval__c (after insert, after update, after delete) {
    List<Approval_Change__e> events = new List<Approval_Change__e>();

    if (Trigger.isInsert || Trigger.isUpdate) {
        for (Approval__c record : Trigger.new) {
            events.add(new Approval_Change__e(
                Record_Id__c = record.Id,
                Change_Type__c = Trigger.isInsert ? 'INSERT' : 'UPDATE'
            ));
        }
    }

    if (Trigger.isDelete) {
        for (Approval__c record : Trigger.old) {
            events.add(new Approval_Change__e(
                Record_Id__c = record.Id,
                Change_Type__c = 'DELETE'
            ));
        }
    }

    if (!events.isEmpty()) {
        EventBus.publish(events);
    }
}
