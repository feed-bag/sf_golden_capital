// Backfill all existing Approval__c records into Supabase by re-publishing
// Approval_Change__e platform events. Exercises the production sync path:
// ApprovalChangeEventTrigger -> ApprovalSupabaseRelay -> approval-sync edge fn.
// Run: sf apex run --file scripts/apex/backfill_approval_sync.apex -o <alias>

List<Approval_Change__e> events = new List<Approval_Change__e>();
for (Approval__c a : [SELECT Id FROM Approval__c]) {
    events.add(new Approval_Change__e(
        Record_Id__c = a.Id,
        Change_Type__c = 'UPSERT'
    ));
}
List<Database.SaveResult> results = EventBus.publish(events);
Integer ok = 0;
Integer fail = 0;
for (Database.SaveResult r : results) {
    if (r.isSuccess()) ok++; else fail++;
}
System.debug('Approval backfill: published=' + events.size() + ' ok=' + ok + ' fail=' + fail);
