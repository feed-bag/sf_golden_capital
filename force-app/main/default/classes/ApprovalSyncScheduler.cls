public with sharing class ApprovalSyncScheduler implements Schedulable {

    // Salesforce CRON does not accept comma lists in the minutes field, so a
    // sub-hourly cadence requires N distinct schedules at staggered offsets.
    // schedule() registers 60 / STEP_MINUTES jobs each hour.
    @TestVisible private static final String BASE_JOB_NAME = 'Approval Supabase Sync';
    @TestVisible private static final Integer STEP_MINUTES = 5;

    public void execute(SchedulableContext ctx) {
        Set<Id> upsertIds = new Set<Id>();
        for (Approval__c a : [SELECT Id FROM Approval__c]) {
            upsertIds.add(a.Id);
        }
        if (!upsertIds.isEmpty()) {
            System.enqueueJob(new ApprovalSupabaseRelay(upsertIds, new Set<Id>()));
        }
    }

    public static List<String> schedule() {
        return schedule(BASE_JOB_NAME);
    }

    public static List<String> schedule(String baseName) {
        List<String> jobIds = new List<String>();
        for (Integer m = 0; m < 60; m += STEP_MINUTES) {
            String minStr = (m < 10 ? '0' : '') + String.valueOf(m);
            String cron = '0 ' + minStr + ' * * * ?';
            String name = baseName + ' :' + minStr;
            jobIds.add(System.schedule(name, cron, new ApprovalSyncScheduler()));
        }
        return jobIds;
    }
}
