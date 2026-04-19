public with sharing class OpportunityDashboardController {

    // ── Field exclusion lists ─────────────────────────────────────────────────
    private static final Set<String> SKIP_FIELD_NAMES = new Set<String>{
        // Already exposed as core columns
        'id','name','stagename','amount','type','closedate','createddate',
        'unique_id__c','laststagechangeindays',
        // Relationship IDs handled by virtual columns (Account, Owner, Dealer)
        'accountid','ownerid','dealer__c',
        // System / audit / internal — not useful to display
        'isdeleted','createdbyid','lastmodifiedbyid','lastmodifieddate',
        'systemmodstamp','lastactivitydate','lastvieweddate','lastreferenceddate',
        'pushedcount','hasopenactivity','hasoverduetask','hasopportunitylineitem',
        'connectionreceivedid','connectionsentid','masterrecordid',
        'pricebook2id','campaignid','forecastcategoryname',
        // Equipment count is internal (formula)
        'equipment_count__c'
    };

    private static final Set<Schema.DisplayType> SKIP_TYPES = new Set<Schema.DisplayType>{
        Schema.DisplayType.BASE64,
        Schema.DisplayType.ADDRESS,
        Schema.DisplayType.LOCATION,
        Schema.DisplayType.ANYTYPE,
        Schema.DisplayType.ID,
        Schema.DisplayType.REFERENCE   // show resolved names via virtual cols, not raw IDs
    };

    // Returns the list of extra fields (beyond the core SELECT) that are safe to query
    private static List<Schema.DescribeFieldResult> getDynamicFields() {
        Map<String, Schema.SObjectField> fieldMap = Schema.SObjectType.Opportunity.fields.getMap();
        List<Schema.DescribeFieldResult> result = new List<Schema.DescribeFieldResult>();
        for (String apiName : fieldMap.keySet()) {
            if (SKIP_FIELD_NAMES.contains(apiName.toLowerCase())) continue;
            Schema.DescribeFieldResult dfr = fieldMap.get(apiName).getDescribe();
            if (!dfr.isAccessible() || SKIP_TYPES.contains(dfr.getType())) continue;
            result.add(dfr);
        }
        return result;
    }

    // ── Public Apex methods ───────────────────────────────────────────────────

    @AuraEnabled(cacheable=true)
    public static List<Opportunity> getOpenOpportunities() {
        return [
            SELECT Id, Name, StageName, Amount, Type,
                   Account.Name, Owner.Name,
                   Dealer__r.Name, Unique_ID__c, LastStageChangeInDays
            FROM Opportunity
            WHERE IsClosed = false
            ORDER BY StageName, Name
        ];
    }

    @AuraEnabled(cacheable=true)
    public static PipelineStats getPipelineStats() {
        PipelineStats stats = new PipelineStats();
        stats.activeDeals = [SELECT COUNT() FROM Opportunity WHERE IsClosed = false];
        stats.dealsThisMonth = [SELECT COUNT() FROM Opportunity WHERE CreatedDate = THIS_MONTH];
        AggregateResult[] funded = [
            SELECT SUM(Amount) total FROM Opportunity
            WHERE StageName IN ('Funded', 'FPC', 'Fully Funded') AND CloseDate = THIS_MONTH
        ];
        stats.volumeFundedThisMonth = (funded[0].get('total') != null)
            ? (Decimal) funded[0].get('total') : 0;
        return stats;
    }

    // Returns metadata for all displayable extra columns (label, apiName, type).
    // Cacheable — schema doesn't change at runtime.
    @AuraEnabled(cacheable=true)
    public static List<Map<String, Object>> getOpportunityFieldMeta() {
        List<Schema.DescribeFieldResult> fields = getDynamicFields();
        List<Map<String, Object>> result = new List<Map<String, Object>>();
        for (Schema.DescribeFieldResult dfr : fields) {
            result.add(new Map<String, Object>{
                'apiName' => dfr.getName(),
                'label'   => dfr.getLabel(),
                'type'    => String.valueOf(dfr.getType())
            });
        }
        return result;
    }

    // Returns all opportunities with core fields + every safe dynamic field.
    @AuraEnabled(cacheable=true)
    public static List<Opportunity> getOpportunitiesForList() {
        List<String> queryFields = new List<String>{
            'Id', 'Name', 'StageName', 'Amount', 'Type', 'CloseDate', 'CreatedDate',
            'Account.Name', 'Owner.Name',
            'Dealer__r.Name', 'Unique_ID__c', 'LastStageChangeInDays'
        };
        for (Schema.DescribeFieldResult dfr : getDynamicFields()) {
            queryFields.add(dfr.getName());
        }
        String soql = 'SELECT ' + String.join(queryFields, ', ')
                    + ' FROM Opportunity ORDER BY Name';
        return Database.query(soql);
    }

    @AuraEnabled(cacheable=true)
    public static List<User> getActiveUsers() {
        return [SELECT Id, Name FROM User WHERE IsActive = true ORDER BY Name LIMIT 500];
    }

    @AuraEnabled
    public static void updateOpportunityStage(Id oppId, String newStage) {
        update new Opportunity(Id = oppId, StageName = newStage);
    }

    @AuraEnabled
    public static void bulkUpdateStage(List<Id> oppIds, String stageName) {
        List<Opportunity> opps = new List<Opportunity>();
        for (Id id : oppIds) opps.add(new Opportunity(Id = id, StageName = stageName));
        update opps;
    }

    @AuraEnabled
    public static void bulkUpdateOwner(List<Id> oppIds, Id ownerId) {
        List<Opportunity> opps = new List<Opportunity>();
        for (Id id : oppIds) opps.add(new Opportunity(Id = id, OwnerId = ownerId));
        update opps;
    }

    @AuraEnabled
    public static void bulkDeleteOpportunities(List<Id> oppIds) {
        List<Opportunity> opps = new List<Opportunity>();
        for (Id id : oppIds) opps.add(new Opportunity(Id = id));
        delete opps;
    }

    public class PipelineStats {
        @AuraEnabled public Integer activeDeals { get; set; }
        @AuraEnabled public Integer dealsThisMonth { get; set; }
        @AuraEnabled public Decimal volumeFundedThisMonth { get; set; }
    }
}
