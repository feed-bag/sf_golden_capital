public with sharing class ApprovalSyncScheduler implements Schedulable {

    // Hourly at :00. Salesforce CRON does not accept comma-lists in the minutes
    // field, so for sub-hourly cadence schedule this class N times at offsets
    // (e.g. '0 15 * * * ?', '0 30 * * * ?', '0 45 * * * ?') under distinct names.
    @TestVisible private static final String DEFAULT_CRON = '0 0 * * * ?';
    @TestVisible private static final String JOB_NAME = 'Approval Supabase Sync';

    public void execute(SchedulableContext ctx) {
        Set<Id> upsertIds = new Set<Id>();
        for (Approval__c a : [SELECT Id FROM Approval__c]) {
            upsertIds.add(a.Id);
        }
        if (!upsertIds.isEmpty()) {
            System.enqueueJob(new ApprovalSupabaseRelay(upsertIds, new Set<Id>()));
        }
    }

    public static String schedule() {
        return System.schedule(JOB_NAME, DEFAULT_CRON, new ApprovalSyncScheduler());
    }
}
