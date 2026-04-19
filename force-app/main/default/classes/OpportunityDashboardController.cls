public with sharing class OpportunityDashboardController {

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

        stats.activeDeals = [
            SELECT COUNT()
            FROM Opportunity
            WHERE IsClosed = false
        ];

        stats.dealsThisMonth = [
            SELECT COUNT()
            FROM Opportunity
            WHERE CreatedDate = THIS_MONTH
        ];

        AggregateResult[] funded = [
            SELECT SUM(Amount) total
            FROM Opportunity
            WHERE StageName IN ('Funded', 'FPC', 'Fully Funded')
            AND CloseDate = THIS_MONTH
        ];
        stats.volumeFundedThisMonth = (funded[0].get('total') != null)
            ? (Decimal) funded[0].get('total')
            : 0;

        return stats;
    }

    @AuraEnabled(cacheable=true)
    public static List<Opportunity> getOpportunitiesForList() {
        return [
            SELECT Id, Name, StageName, Amount, Type, CloseDate, CreatedDate,
                   Account.Name, Owner.Name,
                   Dealer__r.Name, Unique_ID__c, LastStageChangeInDays
            FROM Opportunity
            WHERE IsClosed = false
            ORDER BY Name
        ];
    }

    @AuraEnabled
    public static void updateOpportunityStage(Id oppId, String newStage) {
        Opportunity opp = new Opportunity(Id = oppId, StageName = newStage);
        update opp;
    }

    public class PipelineStats {
        @AuraEnabled public Integer activeDeals { get; set; }
        @AuraEnabled public Integer dealsThisMonth { get; set; }
        @AuraEnabled public Decimal volumeFundedThisMonth { get; set; }
    }
}
