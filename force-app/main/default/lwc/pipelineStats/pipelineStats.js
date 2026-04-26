import { LightningElement, wire, track } from 'lwc';
import { refreshApex } from '@salesforce/apex';
import getDashboardMetrics from '@salesforce/apex/OpportunityDashboardController.getDashboardMetrics';
import getActiveUsers from '@salesforce/apex/OpportunityDashboardController.getActiveUsers';
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

    get hasMetrics() {
        return !!this.metrics;
    }

    get kpiTiles() {
        if (!this.metrics) return [];
        const k = this.metrics.kpis;
        const v = (curr, prev) => deltaMeta(curr, prev);
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
                value: NUMBER_FMT.format(k.newOpportunities || 0),
                hasDelta: true,
                ...v(k.newOpportunities, k.newOpportunitiesPrev)
            }
        ];
    }

    // Inline-SVG bar chart geometry. 12 bars across a 720x180 viewBox with axis room.
    _buildBars(points, isCurrency) {
        const W = 720, H = 180, PAD_L = 8, PAD_R = 8, PAD_T = 16, PAD_B = 28;
        const innerW = W - PAD_L - PAD_R;
        const innerH = H - PAD_T - PAD_B;
        const max = Math.max(1, ...points.map(p => Number(p.value) || 0));
        const slot = innerW / points.length;
        const barW = slot * 0.62;
        return points.map((p, i) => {
            const v = Number(p.value) || 0;
            const h = (v / max) * innerH;
            const x = PAD_L + i * slot + (slot - barW) / 2;
            const y = PAD_T + (innerH - h);
            // Calculate %∆ vs the previous bar so we can show trend hints
            let trendCls = '';
            let trendText = '';
            if (i > 0) {
                const prev = Number(points[i - 1].value) || 0;
                if (prev !== 0 || v !== 0) {
                    const d = prev === 0 ? (v > 0 ? 100 : 0) : ((v - prev) / Math.abs(prev)) * 100;
                    if (Math.abs(d) >= 1) {
                        trendText = (d > 0 ? '+' : '') + d.toFixed(0) + '%';
                        trendCls = d > 0 ? 'ps-bar-trend ps-bar-trend--up' : 'ps-bar-trend ps-bar-trend--down';
                    }
                }
            }
            const valueText = isCurrency
                ? (v >= 1000 ? CURRENCY_COMPACT.format(v) : (v ? '$' + v : ''))
                : (v ? NUMBER_FMT.format(v) : '');
            return {
                key: p.label,
                label: p.label,
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
