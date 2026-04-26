import { LightningElement, wire, track } from 'lwc';
import { refreshApex } from '@salesforce/apex';
import getDashboardMetrics from '@salesforce/apex/OpportunityDashboardController.getDashboardMetrics';
import getActiveUsers from '@salesforce/apex/OpportunityDashboardController.getActiveUsers';
import getOpportunitiesForKpi from '@salesforce/apex/OpportunityDashboardController.getOpportunitiesForKpi';
import bannerUrl from '@salesforce/resourceUrl/golden_cap_banner';

const RANGE_OPTIONS = [
    { value: 'WEEK',    label: 'Week'    },
    { value: 'MONTH',   label: 'Month'   },
    { value: 'QUARTER', label: 'Quarter' },
    { value: 'YEAR',    label: 'Year'    }
];

const CURRENCY_FULL = new Intl.NumberFormat('en-US', {
    style: 'currency', currency: 'USD', maximumFractionDigits: 0
});
const CURRENCY_COMPACT = new Intl.NumberFormat('en-US', {
    style: 'currency', currency: 'USD', notation: 'compact', maximumFractionDigits: 1
});
const NUMBER_FMT = new Intl.NumberFormat('en-US');

function pctDelta(curr, prev) {
    const c = Number(curr) || 0;
    const p = Number(prev) || 0;
    if (p === 0) return c === 0 ? 0 : 100;
    return ((c - p) / Math.abs(p)) * 100;
}
function deltaMeta(curr, prev) {
    const d = pctDelta(curr, prev);
    const sign = d > 0 ? '+' : '';
    return {
        text: `${sign}${d.toFixed(1)}%`,
        cls: d > 0 ? 'ps-delta ps-delta--up' : (d < 0 ? 'ps-delta ps-delta--down' : 'ps-delta ps-delta--flat'),
        hasPrev: (Number(prev) || 0) !== 0 || (Number(curr) || 0) !== 0
    };
}

export default class PipelineStats extends LightningElement {
    bannerUrl = bannerUrl;
    @track timeRange = 'MONTH';
    @track ownerId = null;
    @track userOptions = [];
    metrics;
    error;
    wiredMetrics;

    @track drillKey = null;
    @track drillTitle = '';
    @track drillRows = [];
    @track drillLoading = false;
    @track drillError = null;

    @wire(getActiveUsers)
    wiredUsers({ data }) {
        if (data) {
            this.userOptions = [
                { value: '',  label: 'All Owners' },
                ...data.map(u => ({ value: u.Id, label: u.Name }))
            ];
        }
    }

    @wire(getDashboardMetrics, { timeRange: '$timeRange', ownerId: '$ownerId' })
    wired(result) {
        this.wiredMetrics = result;
        if (result.data) {
            this.metrics = result.data;
            this.error = undefined;
        } else if (result.error) {
            this.error = result.error;
            this.metrics = undefined;
        }
    }

    get rangeButtons() {
        return RANGE_OPTIONS.map(o => ({
            ...o,
            cls: o.value === this.timeRange ? 'ps-range-btn ps-range-btn--active' : 'ps-range-btn'
        }));
    }

    handleRangeClick(event) {
        const next = event.currentTarget.dataset.value;
        if (next && next !== this.timeRange) {
            this.timeRange = next;
        }
    }

    handleOwnerChange(event) {
        const v = event.target.value;
        this.ownerId = v ? v : null;
    }

    handleRefresh() {
        if (this.wiredMetrics) refreshApex(this.wiredMetrics);
    }

    get periodLabel() {
        return this.metrics ? this.metrics.period.label : '';
    }

    get seriesGranularityLabel() {
        switch (this.timeRange) {
            case 'WEEK':    return 'daily';
            case 'MONTH':   return 'weekly';
            case 'QUARTER': return 'monthly';
            case 'YEAR':    return 'monthly';
            default:        return '';
        }
    }

    get hasMetrics() {
        return !!this.metrics;
    }

    get kpiTiles() {
        if (!this.metrics) return [];
        const k = this.metrics.kpis;
        const v = (curr, prev) => deltaMeta(curr, prev);
        const ratio = (num, den) => (den > 0 ? (num / den) * 100 : 0);
        const created     = k.newOpportunities     || 0;
        const createdPrev = k.newOpportunitiesPrev || 0;
        const approvePct     = ratio(k.cohortApproved, created);
        const approvePctPrev = ratio(k.cohortApprovedPrev, createdPrev);
        const fundedPct      = ratio(k.cohortFunded, created);
        const fundedPctPrev  = ratio(k.cohortFundedPrev, createdPrev);
        return [
            {
                key: 'pipeline',
                label: 'Active Pipeline',
                value: CURRENCY_COMPACT.format(k.pipelineValue || 0),
                hasDelta: false
            },
            {
                key: 'volume',
                label: `Volume Funded (${this.periodLabel})`,
                value: CURRENCY_COMPACT.format(k.volumeFunded || 0),
                hasDelta: true,
                ...v(k.volumeFunded, k.volumeFundedPrev)
            },
            {
                key: 'deals',
                label: `Deals Funded (${this.periodLabel})`,
                value: NUMBER_FMT.format(k.dealsFunded || 0),
                hasDelta: true,
                ...v(k.dealsFunded, k.dealsFundedPrev)
            },
            {
                key: 'avg',
                label: `Avg Deal Size (${this.periodLabel})`,
                value: CURRENCY_COMPACT.format(k.avgDealSize || 0),
                hasDelta: true,
                ...v(k.avgDealSize, k.avgDealSizePrev)
            },
            {
                key: 'new',
                label: `New Opportunities (${this.periodLabel})`,
                value: NUMBER_FMT.format(created),
                hasDelta: true,
                ...v(k.newOpportunities, k.newOpportunitiesPrev)
            },
            {
                key: 'approved',
                label: `App → Approved (${this.periodLabel})`,
                value: `${approvePct.toFixed(1)}%`,
                subtext: `${k.cohortApproved || 0} approved / ${created} new`,
                hasDelta: true,
                ...v(approvePct, approvePctPrev)
            },
            {
                key: 'funded',
                label: `App → Funded (${this.periodLabel})`,
                value: `${fundedPct.toFixed(1)}%`,
                subtext: `${k.cohortFunded || 0} funded / ${created} new`,
                hasDelta: true,
                ...v(fundedPct, fundedPctPrev)
            }
        ];
    }

    // Inline-SVG bar chart geometry. Bars span a 720x180 viewBox; bucket count varies by period.
    _buildBars(points, isCurrency) {
        const W = 720, H = 180, PAD_L = 8, PAD_R = 8, PAD_T = 16, PAD_B = 28;
        const innerW = W - PAD_L - PAD_R;
        const innerH = H - PAD_T - PAD_B;
        const n = points.length || 1;
        const max = Math.max(1, ...points.map(p => Number(p.value) || 0));
        const slot = innerW / n;
        const barW = Math.max(2, slot * 0.62);
        // Dense buckets: hide per-bar value labels (overlap), thin axis labels.
        const dense = n > 12;
        const labelEvery = n > 28 ? Math.ceil(n / 12) : (n > 18 ? 2 : 1);
        return points.map((p, i) => {
            const v = Number(p.value) || 0;
            const h = (v / max) * innerH;
            const x = PAD_L + i * slot + (slot - barW) / 2;
            const y = PAD_T + (innerH - h);
            let trendCls = '';
            let trendText = '';
            if (i > 0 && !dense) {
                const prev = Number(points[i - 1].value) || 0;
                if (prev !== 0 || v !== 0) {
                    const d = prev === 0 ? (v > 0 ? 100 : 0) : ((v - prev) / Math.abs(prev)) * 100;
                    if (Math.abs(d) >= 1) {
                        trendText = (d > 0 ? '+' : '') + d.toFixed(0) + '%';
                        trendCls = d > 0 ? 'ps-bar-trend ps-bar-trend--up' : 'ps-bar-trend ps-bar-trend--down';
                    }
                }
            }
            const valueText = dense
                ? ''
                : (isCurrency
                    ? (v >= 1000 ? CURRENCY_COMPACT.format(v) : (v ? '$' + v : ''))
                    : (v ? NUMBER_FMT.format(v) : ''));
            const showLabel = (i % labelEvery === 0) || (i === n - 1);
            return {
                key: p.label + '-' + i,
                label: showLabel ? p.label : '',
                value: v,
                valueText,
                trendText,
                trendCls,
                x, y, w: barW, h,
                labelX: x + barW / 2,
                labelY: H - PAD_B + 16,
                valueY: y - 4,
                trendY: y - 16
            };
        });
    }

    get oppCreatedBars() {
        return this.metrics ? this._buildBars(this.metrics.opportunitiesByMonth, false) : [];
    }

    get volumeFundedBars() {
        return this.metrics ? this._buildBars(this.metrics.volumeFundedByMonth, true) : [];
    }

    // Horizontal bar chart for pipeline by stage.
    get stageBars() {
        if (!this.metrics) return [];
        const rows = this.metrics.pipelineByStage || [];
        const max = Math.max(1, ...rows.map(r => Number(r.total) || 0));
        return rows
            .slice()
            .sort((a, b) => (Number(b.total) || 0) - (Number(a.total) || 0))
            .map(r => {
                const v = Number(r.total) || 0;
                const pct = (v / max) * 100;
                return {
                    key: r.stage,
                    stage: r.stage,
                    count: r.count || 0,
                    valueText: CURRENCY_COMPACT.format(v),
                    barStyle: `width:${pct.toFixed(2)}%;`
                };
            });
    }

    handleKpiClick(event) {
        const key = event.currentTarget.dataset.key;
        if (!key) return;
        const tile = this.kpiTiles.find(t => t.key === key);
        this.drillKey = key;
        this.drillTitle = tile ? tile.label : 'Records';
        this.drillRows = [];
        this.drillError = null;
        this.drillLoading = true;
        getOpportunitiesForKpi({
            kpiKey: key,
            timeRange: this.timeRange,
            ownerId: this.ownerId
        })
            .then(data => {
                this.drillRows = (data || []).map(o => ({
                    id: o.Id,
                    url: '/' + o.Id,
                    name: o.Account ? o.Account.Name : (o.Name || '—'),
                    uniqueId: o.Unique_ID__c || '',
                    stage: o.StageName || '',
                    owner: o.Owner ? o.Owner.Name : '',
                    amountText: o.Amount
                        ? CURRENCY_FULL.format(Number(o.Amount))
                        : '—',
                    fundedDate: o.Funded_Date__c || '',
                    createdDate: o.CreatedDate ? o.CreatedDate.substring(0, 10) : ''
                }));
                this.drillLoading = false;
            })
            .catch(err => {
                this.drillError = err && err.body ? err.body.message : 'Could not load records.';
                this.drillLoading = false;
            });
    }

    handleDrillClose() {
        this.drillKey = null;
        this.drillRows = [];
        this.drillError = null;
    }

    handleDrillBackdropClick(event) {
        if (event.target.classList.contains('ps-modal-backdrop')) {
            this.handleDrillClose();
        }
    }

    get drillOpen() {
        return this.drillKey !== null;
    }

    get drillCountLabel() {
        if (this.drillLoading) return 'Loading…';
        const n = this.drillRows.length;
        if (n === 0) return 'No records';
        if (n >= 200) return '200+ records (capped)';
        return `${n} record${n === 1 ? '' : 's'}`;
    }

    get drillShowFundedCol() {
        return this.drillKey === 'volume' || this.drillKey === 'deals' || this.drillKey === 'avg';
    }

    get drillShowCreatedCol() {
        return this.drillKey === 'new';
    }

    get goalTracker() {
        if (!this.metrics || !this.metrics.annualGoal) return null;
        const g = this.metrics.annualGoal;
        const goal     = Number(g.goal)           || 0;
        const actual   = Number(g.actual)         || 0;
        const expected = Number(g.expectedToDate) || 0;
        const daysIn   = Number(g.daysInYear)     || 365;
        const elapsed  = Number(g.daysElapsed)    || 0;
        const actualPct   = goal > 0 ? Math.min(100, (actual   / goal) * 100) : 0;
        const expectedPct = goal > 0 ? Math.min(100, (expected / goal) * 100) : 0;
        // Project full-year landing if we keep current daily pace.
        const projected = elapsed > 0 ? (actual / elapsed) * daysIn : 0;
        const variance     = actual - expected;
        const variancePct  = expected > 0 ? (variance / expected) * 100 : 0;
        const onPace = variance >= 0;
        return {
            year:           g.year,
            ownerScoped:    g.ownerScoped,
            scopeLabel:     g.ownerScoped ? 'Selected owner' : 'All owners',
            goalText:       CURRENCY_COMPACT.format(goal),
            actualText:     CURRENCY_FULL.format(actual),
            expectedText:   CURRENCY_FULL.format(expected),
            projectedText:  CURRENCY_FULL.format(projected),
            varianceText:   `${variance >= 0 ? '+' : '−'}${CURRENCY_FULL.format(Math.abs(variance))}`,
            variancePctText:`${variance >= 0 ? '+' : ''}${variancePct.toFixed(1)}%`,
            actualPctText:  `${actualPct.toFixed(1)}% of goal`,
            expectedPctText:`${expectedPct.toFixed(1)}% expected by today`,
            actualBarStyle: `width:${actualPct.toFixed(2)}%;`,
            expectedMarkerStyle: `left:${expectedPct.toFixed(2)}%;`,
            onPace,
            statusCls:      onPace ? 'ps-goal-status ps-goal-status--ahead' : 'ps-goal-status ps-goal-status--behind',
            statusText:     onPace ? 'Ahead of pace' : 'Behind pace',
            daysLabel:      `Day ${elapsed} of ${daysIn}`
        };
    }

    get hasGoalTracker() {
        return this.goalTracker !== null;
    }

    get hasTopOwners() {
        return this.metrics && this.metrics.topOwners && this.metrics.topOwners.length > 0;
    }

    get topOwnerRows() {
        if (!this.metrics) return [];
        return (this.metrics.topOwners || []).map((o, i) => ({
            key: o.ownerId,
            rank: i + 1,
            ownerName: o.ownerName,
            volumeText: CURRENCY_FULL.format(Number(o.volumeFunded) || 0),
            dealsText: NUMBER_FMT.format(Number(o.dealsFunded) || 0)
        }));
    }
}
