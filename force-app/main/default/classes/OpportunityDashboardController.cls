public with sharing class OpportunityDashboardController {

    // ── Field exclusion lists ─────────────────────────────────────────────────
    private static final Set<String> SKIP_FIELD_NAMES = new Set<String>{
        // Already exposed as core columns
        'id','name','stagename','amount','type','closedate','createddate',
        'unique_id__c','laststagechangeindays',
        // Relationship IDs handled by virtual columns (Account, Owner)
        'accountid','ownerid',
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
    public static String getBoxFolderId(Id recordId) {
        Opportunity opp = [SELECT Box_Folder_ID__c FROM Opportunity WHERE Id = :recordId LIMIT 1];
        return opp.Box_Folder_ID__c;
    }

    @AuraEnabled(cacheable=true)
    public static List<Opportunity> getOpenOpportunities() {
        return [
            SELECT Id, Name, StageName, Amount, Type, OwnerId,
                   Account.Name, Owner.Name,
                   Unique_ID__c, LastStageChangeInDays,
                   Private_Party__c, On_Hold__c,
                   (SELECT Id, Dealer__c, Dealer__r.Name FROM Equipment__r)
            FROM Opportunity
            WHERE IsClosed = false
            ORDER BY StageName, Name
        ];
    }

    @AuraEnabled(cacheable=true)
    public static List<Map<String, Object>> getDealersForOpportunity(Id oppId) {
        Map<Id, String> distinctDealers = new Map<Id, String>();
        for (Equipment__c e : [
            SELECT Dealer__c, Dealer__r.Name
            FROM Equipment__c
            WHERE Opportunity__c = :oppId AND Dealer__c != null
        ]) {
            distinctDealers.put(e.Dealer__c, e.Dealer__r.Name);
        }
        List<Map<String, Object>> result = new List<Map<String, Object>>();
        for (Id dealerId : distinctDealers.keySet()) {
            result.add(new Map<String, Object>{
                'id'   => dealerId,
                'name' => distinctDealers.get(dealerId)
            });
        }
        result.sort(new DealerNameComparator());
        return result;
    }

    private class DealerNameComparator implements System.Comparator<Map<String, Object>> {
        public Integer compare(Map<String, Object> a, Map<String, Object> b) {
            String an = String.valueOf(a.get('name'));
            String bn = String.valueOf(b.get('name'));
            return an.compareTo(bn);
        }
    }

    // Returns every cic_credit__Credit_Report__c whose Contact sits on the Opportunity's Account.
    // Powers the Credit Reports tab on the Opportunity record page.
    @AuraEnabled(cacheable=true)
    public static List<Map<String, Object>> getCreditReportsForOpportunity(Id oppId) {
        List<Map<String, Object>> result = new List<Map<String, Object>>();
        if (oppId == null) return result;

        List<Opportunity> opps = [SELECT AccountId FROM Opportunity WHERE Id = :oppId LIMIT 1];
        if (opps.isEmpty() || opps[0].AccountId == null) return result;
        Id accountId = opps[0].AccountId;

        Set<Id> contactIds = new Map<Id, Contact>([
            SELECT Id FROM Contact WHERE AccountId = :accountId
        ]).keySet();
        if (contactIds.isEmpty()) return result;

        for (cic_credit__Credit_Report__c r : [
            SELECT Id, Name, CreatedDate,
                   cic_credit__Contact__c, cic_credit__Contact__r.Name,
                   cic_credit__Score__c,
                   cic_credit__Open_Tradelines__c, cic_credit__Closed_Tradelines__c,
                   cic_credit__Collections__c, cic_credit__Public_Records__c
            FROM cic_credit__Credit_Report__c
            WHERE cic_credit__Contact__c IN :contactIds
            WITH USER_MODE
            ORDER BY CreatedDate DESC
            LIMIT 200
        ]) {
            result.add(new Map<String, Object>{
                'id'              => r.Id,
                'name'            => r.Name,
                'recordUrl'       => '/' + r.Id,
                'createdDate'     => r.CreatedDate,
                'contactId'       => r.cic_credit__Contact__c,
                'contactName'     => r.cic_credit__Contact__r != null ? r.cic_credit__Contact__r.Name : null,
                'contactUrl'      => r.cic_credit__Contact__c != null ? '/' + r.cic_credit__Contact__c : null,
                'score'           => r.cic_credit__Score__c,
                'openTradelines'  => r.cic_credit__Open_Tradelines__c,
                'closedTradelines'=> r.cic_credit__Closed_Tradelines__c,
                'collections'     => r.cic_credit__Collections__c,
                'publicRecords'   => r.cic_credit__Public_Records__c
            });
        }
        return result;
    }

    @AuraEnabled(cacheable=true)
    public static PipelineStats getPipelineStats() {
        PipelineStats stats = new PipelineStats();
        stats.activeDeals = [SELECT COUNT() FROM Opportunity WHERE IsClosed = false];
        stats.dealsThisMonth = [SELECT COUNT() FROM Opportunity WHERE CreatedDate = THIS_MONTH];
        AggregateResult[] funded = [
            SELECT SUM(Amount) total FROM Opportunity
            WHERE Funded_Date__c = THIS_MONTH
        ];
        stats.volumeFundedThisMonth = (funded[0].get('total') != null)
            ? (Decimal) funded[0].get('total') : 0;
        return stats;
    }

    // ── Dashboard metrics ────────────────────────────────────────────────────
    // Returns the full payload powering the Metrics tab in one round-trip.
    // timeRange ∈ {'WEEK','MONTH','QUARTER','YEAR'}; ownerId is optional.
    @AuraEnabled(cacheable=true)
    public static DashboardMetrics getDashboardMetrics(String timeRange, Id ownerId) {
        DashboardMetrics m = new DashboardMetrics();

        Period current  = resolvePeriod(timeRange == null ? 'MONTH' : timeRange.toUpperCase(), 0);
        Period previous = resolvePeriod(timeRange == null ? 'MONTH' : timeRange.toUpperCase(), -1);
        m.period = current;

        m.kpis             = computeKpis(current, previous, ownerId);
        m.opportunitiesByMonth = computeSeries(current, ownerId, 'CREATED');
        m.volumeFundedByMonth  = computeSeries(current, ownerId, 'FUNDED');
        m.pipelineByStage  = computePipelineByStage(ownerId);
        m.topOwners        = (ownerId == null) ? computeTopOwners(current) : new List<OwnerPerformance>();
        m.annualGoal       = computeAnnualGoal(ownerId);

        return m;
    }

    // Annual funding goal vs actual + on-pace expectation. Goal is intentionally hardcoded for now;
    // promote to a Custom Metadata Type if it needs to vary by org or by year.
    private static AnnualGoal computeAnnualGoal(Id ownerId) {
        Date today = Date.today();
        Date yearStart = Date.newInstance(today.year(), 1, 1);
        Date yearEnd   = Date.newInstance(today.year(), 12, 31);

        AggregateResult[] rows = Database.queryWithBinds(
            'SELECT SUM(Amount) total FROM Opportunity ' +
            'WHERE Funded_Date__c >= :yearStart AND Funded_Date__c <= :yearEnd' + ownerClause(ownerId),
            new Map<String, Object>{
                'yearStart' => yearStart, 'yearEnd' => yearEnd, 'ownerId' => ownerId
            },
            AccessLevel.USER_MODE
        );

        AnnualGoal g = new AnnualGoal();
        g.goal           = 10000000;
        g.actual         = decOrZero(rows[0], 'total');
        g.daysInYear     = yearStart.daysBetween(yearEnd) + 1;
        g.daysElapsed    = Math.min(yearStart.daysBetween(today) + 1, g.daysInYear);
        g.expectedToDate = (g.goal * g.daysElapsed) / g.daysInYear;
        g.year           = today.year();
        g.ownerScoped    = ownerId != null;
        return g;
    }

    // KPI tile drill-down. Returns up to 200 opps behind a given tile, respecting the same
    // time range + owner filter the dashboard is currently using.
    @AuraEnabled(cacheable=true)
    public static List<Opportunity> getOpportunitiesForKpi(String kpiKey, String timeRange, Id ownerId) {
        Period cur = resolvePeriod(timeRange == null ? 'MONTH' : timeRange.toUpperCase(), 0);
        String filter;
        String orderBy;
        Map<String, Object> binds = new Map<String, Object>{
            'curStart' => cur.startDate, 'curEnd' => cur.endDate, 'ownerId' => ownerId
        };
        if (kpiKey == 'pipeline') {
            filter  = 'IsClosed = false';
            orderBy = 'Amount DESC NULLS LAST';
        } else if (kpiKey == 'new') {
            filter  = 'CreatedDate >= :curStart AND CreatedDate <= :curEnd';
            orderBy = 'CreatedDate DESC';
        } else if (kpiKey == 'approved') {
            // Pace: opps that received an Approval child record during the period.
            filter  = 'Id IN (SELECT Opportunity__c FROM Approval__c ' +
                      'WHERE CreatedDate >= :curStart AND CreatedDate <= :curEnd)';
            orderBy = 'LastModifiedDate DESC';
        } else if (kpiKey == 'funded') {
            // Pace: opps funded in the period (Funded_Date__c falls in the window).
            filter  = 'Funded_Date__c >= :curStart AND Funded_Date__c <= :curEnd';
            orderBy = 'Funded_Date__c DESC';
        } else {
            // volume / deals / avg → opps funded in the period
            filter  = 'Funded_Date__c >= :curStart AND Funded_Date__c <= :curEnd';
            orderBy = 'Funded_Date__c DESC NULLS LAST, Amount DESC NULLS LAST';
        }
        String soql =
            'SELECT Id, Name, StageName, Amount, OwnerId, Owner.Name, Account.Name, ' +
            '       Unique_ID__c, CloseDate, CreatedDate, Funded_Date__c ' +
            'FROM Opportunity WHERE ' + filter + ownerClause(ownerId) +
            ' ORDER BY ' + orderBy + ' LIMIT 200';
        return Database.queryWithBinds(soql, binds, AccessLevel.USER_MODE);
    }

    // Period boundaries. offset = 0 → current period; -1 → immediately preceding period of same length.
    private static Period resolvePeriod(String range, Integer offset) {
        Date today = Date.today();
        Date startD;
        Date endD;
        String label;
        if (range == 'WEEK') {
            // Rolling 7-day windows ending today.
            endD   = today.addDays(7 * offset);
            startD = endD.addDays(-6);
            label  = (offset == 0) ? 'This Week' : 'Last Week';
        } else if (range == 'QUARTER') {
            Integer m0  = ((today.month() - 1) / 3) * 3 + 1;
            Date qStart = Date.newInstance(today.year(), m0, 1).addMonths(3 * offset);
            Date qEnd   = qStart.addMonths(3).addDays(-1);
            startD = qStart;
            endD   = qEnd;
            label  = (offset == 0) ? 'This Quarter' : 'Last Quarter';
        } else if (range == 'YEAR') {
            startD = Date.newInstance(today.year() + offset, 1, 1);
            endD   = Date.newInstance(today.year() + offset, 12, 31);
            label  = (offset == 0) ? 'This Year' : 'Last Year';
        } else {
            // MONTH (default)
            startD = Date.newInstance(today.year(), today.month(), 1).addMonths(offset);
            endD   = startD.addMonths(1).addDays(-1);
            label  = (offset == 0) ? 'This Month' : 'Last Month';
        }
        Period p = new Period();
        p.range = range;
        p.label = label;
        p.startDate = startD;
        p.endDate   = endD;
        return p;
    }

    private static String ownerClause(Id ownerId) {
        return ownerId == null ? '' : ' AND OwnerId = :ownerId ';
    }

    private static KpiSet computeKpis(Period cur, Period prev, Id ownerId) {
        KpiSet k = new KpiSet();

        // Pipeline value (open opps, current snapshot — no time filter)
        AggregateResult[] pipeline = Database.queryWithBinds(
            'SELECT SUM(Amount) total FROM Opportunity WHERE IsClosed = false' + ownerClause(ownerId),
            new Map<String, Object>{'ownerId' => ownerId}, AccessLevel.USER_MODE
        );
        k.pipelineValue = decOrZero(pipeline[0], 'total');

        // Period-bound aggregates: funded volume + funded count + new opps
        Map<String, Object> binds = new Map<String, Object>{
            'curStart'  => cur.startDate,  'curEnd'  => cur.endDate,
            'prevStart' => prev.startDate, 'prevEnd' => prev.endDate,
            'ownerId'   => ownerId
        };

        AggregateResult[] curFunded = Database.queryWithBinds(
            'SELECT SUM(Amount) total, COUNT(Id) cnt FROM Opportunity ' +
            'WHERE Funded_Date__c >= :curStart AND Funded_Date__c <= :curEnd' + ownerClause(ownerId),
            binds, AccessLevel.USER_MODE
        );
        AggregateResult[] prevFunded = Database.queryWithBinds(
            'SELECT SUM(Amount) total, COUNT(Id) cnt FROM Opportunity ' +
            'WHERE Funded_Date__c >= :prevStart AND Funded_Date__c <= :prevEnd' + ownerClause(ownerId),
            binds, AccessLevel.USER_MODE
        );
        AggregateResult[] curCreated = Database.queryWithBinds(
            'SELECT COUNT(Id) cnt FROM Opportunity ' +
            'WHERE CreatedDate >= :curStart AND CreatedDate <= :curEnd' + ownerClause(ownerId),
            binds, AccessLevel.USER_MODE
        );
        AggregateResult[] prevCreated = Database.queryWithBinds(
            'SELECT COUNT(Id) cnt FROM Opportunity ' +
            'WHERE CreatedDate >= :prevStart AND CreatedDate <= :prevEnd' + ownerClause(ownerId),
            binds, AccessLevel.USER_MODE
        );
        // Pace ratios: count of approval/funding events in the period (independent of when the
        // parent opp was created), used as numerator over period-created for the App→X ratios.
        // Approval events come from Approval__c child records; the moment one is created marks
        // when the opp first reached approval.
        String approvalOwnerClause = ownerId == null ? '' : ' AND Opportunity__r.OwnerId = :ownerId ';
        AggregateResult[] curApproved = Database.queryWithBinds(
            'SELECT COUNT_DISTINCT(Opportunity__c) cnt FROM Approval__c ' +
            'WHERE CreatedDate >= :curStart AND CreatedDate <= :curEnd' + approvalOwnerClause,
            binds, AccessLevel.USER_MODE
        );
        AggregateResult[] prevApproved = Database.queryWithBinds(
            'SELECT COUNT_DISTINCT(Opportunity__c) cnt FROM Approval__c ' +
            'WHERE CreatedDate >= :prevStart AND CreatedDate <= :prevEnd' + approvalOwnerClause,
            binds, AccessLevel.USER_MODE
        );
        // Funded-in-period is the same population already counted as dealsFunded above; reuse it.

        k.volumeFunded     = decOrZero(curFunded[0],  'total');
        k.volumeFundedPrev = decOrZero(prevFunded[0], 'total');
        k.dealsFunded      = intOrZero(curFunded[0],  'cnt');
        k.dealsFundedPrev  = intOrZero(prevFunded[0], 'cnt');
        k.newOpportunities     = intOrZero(curCreated[0],  'cnt');
        k.newOpportunitiesPrev = intOrZero(prevCreated[0], 'cnt');
        k.avgDealSize     = (k.dealsFunded     > 0) ? (k.volumeFunded     / k.dealsFunded)     : 0;
        k.avgDealSizePrev = (k.dealsFundedPrev > 0) ? (k.volumeFundedPrev / k.dealsFundedPrev) : 0;

        // Pace numerators (independent populations counted in the period); ratios computed in the LWC
        // against newOpportunities. Funded-in-period reuses the dealsFunded count above.
        k.cohortApproved     = intOrZero(curApproved[0],  'cnt');
        k.cohortApprovedPrev = intOrZero(prevApproved[0], 'cnt');
        k.cohortFunded       = k.dealsFunded;
        k.cohortFundedPrev   = k.dealsFundedPrev;

        return k;
    }

    // Range-aware time series. Granularity scales to the selected period:
    //   WEEK    → 7 daily buckets (Mon–Sun of the week)
    //   MONTH   → 4–5 weekly buckets (Week 1 = days 1–7, Week 2 = 8–14, …)
    //   QUARTER → 3 monthly buckets
    //   YEAR    → 12 monthly buckets
    // metric ∈ {'CREATED','FUNDED'}. CREATED counts opps by CreatedDate; FUNDED sums Amount by Funded_Date__c.
    private static List<MonthlyPoint> computeSeries(Period p, Id ownerId, String metric) {
        Boolean isCreated = (metric == 'CREATED');
        String dateField = isCreated ? 'CreatedDate' : 'Funded_Date__c';

        // Pull the matching records (capped to keep the query bounded; one record per opp).
        String soql = 'SELECT ' + dateField + ', Amount FROM Opportunity ' +
            'WHERE ' + dateField + ' >= :startDt AND ' + dateField + ' <= :endDt' +
            ownerClause(ownerId) + ' LIMIT 50000';
        List<Opportunity> rows = Database.queryWithBinds(soql,
            new Map<String, Object>{'startDt' => p.startDate, 'endDt' => p.endDate, 'ownerId' => ownerId},
            AccessLevel.USER_MODE);

        // Build empty buckets for the period so missing slots render as zero.
        List<MonthlyPoint> buckets = buildBuckets(p);
        Map<String, MonthlyPoint> byKey = new Map<String, MonthlyPoint>();
        for (MonthlyPoint b : buckets) byKey.put(b.bucketKey, b);

        for (Opportunity o : rows) {
            Date d = isCreated ? o.CreatedDate.date() : o.Funded_Date__c;
            if (d == null) continue;
            String k = bucketKeyFor(p.range, d);
            MonthlyPoint b = byKey.get(k);
            if (b == null) continue;
            if (isCreated) {
                b.value = (b.value == null ? 0 : b.value) + 1;
            } else {
                Decimal amt = (o.Amount == null) ? 0 : o.Amount;
                b.value = (b.value == null ? 0 : b.value) + amt;
            }
        }
        return buckets;
    }

    private static List<MonthlyPoint> buildBuckets(Period p) {
        List<MonthlyPoint> out = new List<MonthlyPoint>();
        if (p.range == 'YEAR') {
            for (Integer i = 0; i < 12; i++) {
                Date d = Date.newInstance(p.startDate.year(), i + 1, 1);
                MonthlyPoint mp = new MonthlyPoint();
                mp.year = d.year();
                mp.month = d.month();
                mp.label = monthLabel(d.month());
                mp.bucketKey = d.year() + '-M-' + d.month();
                mp.value = 0;
                out.add(mp);
            }
        } else if (p.range == 'QUARTER') {
            // 3 monthly buckets covering the quarter.
            for (Integer i = 0; i < 3; i++) {
                Date d = Date.newInstance(p.startDate.year(), p.startDate.month() + i, 1);
                MonthlyPoint mp = new MonthlyPoint();
                mp.year = d.year();
                mp.month = d.month();
                mp.label = monthLabel(d.month());
                mp.bucketKey = d.year() + '-M-' + d.month();
                mp.value = 0;
                out.add(mp);
            }
        } else if (p.range == 'MONTH') {
            // Weekly buckets within the month: Wk 1 = days 1–7, Wk 2 = 8–14, etc.
            Integer daysInMonth = p.startDate.daysBetween(p.endDate) + 1;
            Integer weeks = (Integer) Math.ceil(daysInMonth / 7.0);
            for (Integer i = 0; i < weeks; i++) {
                Integer firstDay = i * 7 + 1;
                Integer lastDay  = Math.min((i + 1) * 7, daysInMonth);
                MonthlyPoint mp = new MonthlyPoint();
                mp.year  = p.startDate.year();
                mp.month = p.startDate.month();
                mp.label = monthLabel(p.startDate.month()) + ' ' + firstDay + '–' + lastDay;
                mp.bucketKey = p.startDate.year() + '-WoM-' + p.startDate.month() + '-' + i;
                mp.value = 0;
                out.add(mp);
            }
        } else {
            // WEEK → daily buckets.
            Date cursor = p.startDate;
            while (cursor <= p.endDate) {
                MonthlyPoint mp = new MonthlyPoint();
                mp.year  = cursor.year();
                mp.month = cursor.month();
                mp.label = shortDow(cursor) + ' ' + cursor.day();
                mp.bucketKey = cursor.year() + '-D-' + cursor.month() + '-' + cursor.day();
                mp.value = 0;
                out.add(mp);
                cursor = cursor.addDays(1);
            }
        }
        return out;
    }

    private static String bucketKeyFor(String range, Date d) {
        if (range == 'YEAR' || range == 'QUARTER') return d.year() + '-M-' + d.month();
        if (range == 'MONTH') {
            // Index by week-of-month (zero-based). Day 1–7 → 0, 8–14 → 1, etc.
            Integer weekIdx = (d.day() - 1) / 7;
            return d.year() + '-WoM-' + d.month() + '-' + weekIdx;
        }
        return d.year() + '-D-' + d.month() + '-' + d.day();
    }

    private static String shortDow(Date d) {
        DateTime dt = DateTime.newInstance(d.year(), d.month(), d.day());
        return dt.format('EEE');
    }

    private static List<StageBucket> computePipelineByStage(Id ownerId) {
        AggregateResult[] rows = Database.queryWithBinds(
            'SELECT StageName stage, SUM(Amount) total, COUNT(Id) cnt ' +
            'FROM Opportunity WHERE IsClosed = false' + ownerClause(ownerId) + ' ' +
            'GROUP BY StageName',
            new Map<String, Object>{'ownerId' => ownerId},
            AccessLevel.USER_MODE
        );
        List<StageBucket> out = new List<StageBucket>();
        for (AggregateResult ar : rows) {
            StageBucket b = new StageBucket();
            b.stage = (String) ar.get('stage');
            b.total = decOrZero(ar, 'total');
            b.count = intOrZero(ar, 'cnt');
            out.add(b);
        }
        return out;
    }

    private static List<OwnerPerformance> computeTopOwners(Period cur) {
        AggregateResult[] rows = Database.queryWithBinds(
            'SELECT OwnerId ownerId, SUM(Amount) total, COUNT(Id) cnt ' +
            'FROM Opportunity ' +
            'WHERE Funded_Date__c >= :curStart AND Funded_Date__c <= :curEnd ' +
            'GROUP BY OwnerId ORDER BY SUM(Amount) DESC NULLS LAST LIMIT 5',
            new Map<String, Object>{'curStart' => cur.startDate, 'curEnd' => cur.endDate},
            AccessLevel.USER_MODE
        );
        Set<Id> ownerIds = new Set<Id>();
        for (AggregateResult ar : rows) ownerIds.add((Id) ar.get('ownerId'));
        Map<Id, User> users = new Map<Id, User>([SELECT Id, Name FROM User WHERE Id IN :ownerIds]);

        List<OwnerPerformance> out = new List<OwnerPerformance>();
        for (AggregateResult ar : rows) {
            OwnerPerformance op = new OwnerPerformance();
            Id oid = (Id) ar.get('ownerId');
            op.ownerId = oid;
            op.ownerName = users.containsKey(oid) ? users.get(oid).Name : 'Unknown';
            op.volumeFunded = decOrZero(ar, 'total');
            op.dealsFunded  = intOrZero(ar, 'cnt');
            out.add(op);
        }
        return out;
    }

    private static Decimal decOrZero(AggregateResult ar, String alias) {
        Object v = ar.get(alias);
        return v == null ? 0 : (Decimal) v;
    }
    private static Integer intOrZero(AggregateResult ar, String alias) {
        Object v = ar.get(alias);
        return v == null ? 0 : (Integer) v;
    }
    private static String monthLabel(Integer m) {
        return new List<String>{
            'Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'
        }[m - 1];
    }

    // ── DTOs for the dashboard payload ───────────────────────────────────────
    public class DashboardMetrics {
        @AuraEnabled public Period period;
        @AuraEnabled public KpiSet kpis;
        @AuraEnabled public List<MonthlyPoint> opportunitiesByMonth;
        @AuraEnabled public List<MonthlyPoint> volumeFundedByMonth;
        @AuraEnabled public List<StageBucket> pipelineByStage;
        @AuraEnabled public List<OwnerPerformance> topOwners;
        @AuraEnabled public AnnualGoal annualGoal;
    }
    public class AnnualGoal {
        @AuraEnabled public Decimal goal;
        @AuraEnabled public Decimal actual;
        @AuraEnabled public Decimal expectedToDate;
        @AuraEnabled public Integer daysInYear;
        @AuraEnabled public Integer daysElapsed;
        @AuraEnabled public Integer year;
        @AuraEnabled public Boolean ownerScoped;
    }
    public class Period {
        @AuraEnabled public String range;
        @AuraEnabled public String label;
        @AuraEnabled public Date startDate;
        @AuraEnabled public Date endDate;
    }
    public class KpiSet {
        @AuraEnabled public Decimal pipelineValue;
        @AuraEnabled public Decimal volumeFunded;
        @AuraEnabled public Decimal volumeFundedPrev;
        @AuraEnabled public Integer dealsFunded;
        @AuraEnabled public Integer dealsFundedPrev;
        @AuraEnabled public Decimal avgDealSize;
        @AuraEnabled public Decimal avgDealSizePrev;
        @AuraEnabled public Integer newOpportunities;
        @AuraEnabled public Integer newOpportunitiesPrev;
        @AuraEnabled public Integer cohortApproved;
        @AuraEnabled public Integer cohortApprovedPrev;
        @AuraEnabled public Integer cohortFunded;
        @AuraEnabled public Integer cohortFundedPrev;
    }
    public class MonthlyPoint {
        @AuraEnabled public Integer year;
        @AuraEnabled public Integer month;
        @AuraEnabled public String  label;
        @AuraEnabled public Decimal value;
        // Internal — used to merge query results into the pre-built bucket list.
        public String bucketKey;
    }
    public class StageBucket {
        @AuraEnabled public String  stage;
        @AuraEnabled public Decimal total;
        @AuraEnabled public Integer count;
    }
    public class OwnerPerformance {
        @AuraEnabled public Id      ownerId;
        @AuraEnabled public String  ownerName;
        @AuraEnabled public Decimal volumeFunded;
        @AuraEnabled public Integer dealsFunded;
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
            'Unique_ID__c', 'LastStageChangeInDays'
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

    @AuraEnabled(cacheable=true)
    public static String getColumnPreference() {
        List<List_Column_Pref__c> prefs = [
            SELECT Columns__c FROM List_Column_Pref__c
            WHERE OwnerId = :UserInfo.getUserId() LIMIT 1
        ];
        return prefs.isEmpty() ? null : prefs[0].Columns__c;
    }

    @AuraEnabled
    public static void saveColumnPreference(String colsJson) {
        List<List_Column_Pref__c> existing = [
            SELECT Id FROM List_Column_Pref__c
            WHERE OwnerId = :UserInfo.getUserId() LIMIT 1
        ];
        if (!existing.isEmpty()) {
            update new List_Column_Pref__c(Id = existing[0].Id, Columns__c = colsJson);
        } else {
            insert new List_Column_Pref__c(Columns__c = colsJson);
        }
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