import { LightningElement, wire, track } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { refreshApex } from '@salesforce/apex';
import userId from '@salesforce/user/Id';
import getOpenOpportunities from '@salesforce/apex/OpportunityDashboardController.getOpenOpportunities';
import updateOpportunityStage from '@salesforce/apex/OpportunityDashboardController.updateOpportunityStage';

const STAGES = [
    'App In',
    'Sales Follow Up',
    'On Hold',
    'Internal Review',
    'Submitted',
    'Approved',
    'Pre Docs',
    'Docs Requested',
    'Docs Out',
    'Funding Request Sent',
    'Funded',
    'FPC'
];

const TYPE_TAG_COLORS = {
    'Equipment':       { bg: 'rgba(210,154,46,0.18)',   color: '#6b4400' },
    'Working Capital': { bg: 'rgba(58,90,138,0.18)',    color: '#1a3060' },
    'New Business':    { bg: 'rgba(90,122,176,0.18)',   color: '#2a3d5e' },
};
const TYPE_TAG_FALLBACK = [
    { bg: 'rgba(194,145,46,0.16)',  color: '#7a5200' },
    { bg: 'rgba(42,61,94,0.16)',    color: '#253551' },
    { bg: 'rgba(122,160,208,0.16)', color: '#1e3560' },
];
const DEALER_TAG_STYLE = 'background:rgba(37,53,81,0.10); color:#253551; border:1px solid rgba(37,53,81,0.18);';

const STAGE_PROGRESS = {
    'App In': 8, 'Sales Follow Up': 17, 'On Hold': 25,
    'Internal Review': 33, 'Submitted': 42, 'Approved': 50,
    'Pre Docs': 58, 'Docs Requested': 67, 'Docs Out': 75,
    'Funding Request Sent': 83, 'Funded': 92, 'FPC': 100
};

function stalenessColor(days) {
    if (days <= 1)  return '#97C459';
    if (days <= 3)  return '#C8D96A';
    if (days <= 6)  return '#EF9F27';
    if (days <= 13) return '#E8804A';
    return '#E24B4A';
}

const AVATAR_PALETTES = [
    { bg: '#EEEDFE', fg: '#3C3489' },
    { bg: '#E1F5EE', fg: '#085041' },
    { bg: '#FAEEDA', fg: '#633806' },
    { bg: '#FCEBEB', fg: '#791F1F' },
    { bg: '#EAF3DE', fg: '#27500A' },
    { bg: '#E6F1FB', fg: '#0C447C' },
    { bg: '#F3EBF9', fg: '#5C2D7C' },
];

const currencyFormatter = new Intl.NumberFormat('en-US', {
    style: 'currency',
    currency: 'USD',
    maximumFractionDigits: 0
});

function getInitials(fullName) {
    if (!fullName) return '?';
    const parts = fullName.trim().split(/\s+/);
    if (parts.length === 1) return parts[0][0].toUpperCase();
    return (parts[0][0] + parts[parts.length - 1][0]).toUpperCase();
}

function hashIndex(str, len) {
    let h = 0;
    for (let i = 0; i < str.length; i++) h = (h * 31 + str.charCodeAt(i)) & 0xffff;
    return h % len;
}

export default class OpportunityKanban extends LightningElement {
    @track columns;
    @track isLoading = true;
    @track error;
    @track filterOwnerId;

    _allOpps = [];
    _currentUserId = userId;
    draggedOppId;
    wiredResult;

    connectedCallback() {
        this.filterOwnerId = this._currentUserId;
    }

    @wire(getOpenOpportunities)
    wiredOpportunities(result) {
        this.wiredResult = result;
        this.isLoading = false;
        if (result.data) {
            this.error = undefined;
            this._allOpps = result.data;
            this._applyFilter();
        } else if (result.error) {
            this.error = result.error;
            this.columns = undefined;
        }
    }

    get ownerOptions() {
        const seen = new Map();
        this._allOpps.forEach(opp => {
            if (opp.OwnerId && opp.Owner && !seen.has(opp.OwnerId)) {
                seen.set(opp.OwnerId, opp.Owner.Name);
            }
        });
        const options = [{ label: 'All Opportunities', value: '' }];
        seen.forEach((name, id) => {
            const label = id === this._currentUserId ? `My Opportunities (${name})` : name;
            options.push({ label, value: id });
        });
        options.sort((a, b) => {
            if (!a.value) return -1;
            if (!b.value) return 1;
            if (a.value === this._currentUserId) return -1;
            if (b.value === this._currentUserId) return 1;
            return a.label.localeCompare(b.label);
        });
        return options.map(o => ({ ...o, selected: o.value === (this.filterOwnerId || '') }));
    }

    get filterLabel() {
        const opt = this.ownerOptions.find(o => o.value === (this.filterOwnerId || ''));
        return opt ? opt.label : 'All Opportunities';
    }

    handleOwnerFilter(event) {
        this.filterOwnerId = event.target.value || null;
        this._applyFilter();
    }

    _applyFilter() {
        const filtered = this.filterOwnerId
            ? this._allOpps.filter(opp => opp.OwnerId === this.filterOwnerId)
            : this._allOpps;
        this.buildColumns(filtered);
    }

    buildColumns(opportunities) {
        const map = {};
        STAGES.forEach(stage => { map[stage] = []; });

        opportunities.forEach(opp => {
            if (map[opp.StageName] === undefined) return;

            const daysInStage = opp.LastStageChangeInDays || 0;
            const staleColor = stalenessColor(daysInStage);
            const progress = STAGE_PROGRESS[opp.StageName] || 0;
            const ownerName = opp.Owner ? opp.Owner.Name : '';
            const palette = AVATAR_PALETTES[hashIndex(ownerName, AVATAR_PALETTES.length)];

            const tags = [];
            if (opp.Type) {
                const tc = TYPE_TAG_COLORS[opp.Type] || TYPE_TAG_FALLBACK[hashIndex(opp.Type, TYPE_TAG_FALLBACK.length)];
                tags.push({ key: 'type', label: opp.Type, tagStyle: `background:${tc.bg}; color:${tc.color};` });
            }
            if (opp.Dealer__r) tags.push({ key: 'dealer', label: opp.Dealer__r.Name, tagStyle: DEALER_TAG_STYLE });

            map[opp.StageName].push({
                Id: opp.Id,
                url: '/' + opp.Id,
                accountName: opp.Account ? opp.Account.Name : opp.Name,
                uniqueId: opp.Unique_ID__c || '',
                tags,
                rawAmount: opp.Amount || 0,
                amountFormatted: opp.Amount ? currencyFormatter.format(opp.Amount) : null,
                stageStripStyle: `background:${staleColor};`,
                progressFillStyle: `width:${progress}%; background:#9b9b9b;`,
                progressPct: progress + '%',
                ownerInitials: getInitials(ownerName),
                ownerName,
                ownerAvatarStyle: `background:${palette.bg}; color:${palette.fg};`,
                daysInStageLabel: daysInStage === 0 ? 'Today' : `${daysInStage}d`,
                dotStyle: `background:${staleColor};`
            });
        });

        this.columns = STAGES.map(stage => {
            const opps = map[stage];
            const total = opps.reduce((sum, o) => sum + (o.rawAmount || 0), 0);
            return {
                stage,
                opportunities: opps,
                count: opps.length,
                totalFormatted: total > 0 ? currencyFormatter.format(total) : null
            };
        });
    }

    handleDragStart(event) {
        const id = event.currentTarget.dataset.id;
        this.draggedOppId = id;
        const sourceCol = this.columns.find(col => col.opportunities.some(o => o.Id === id));
        this.draggedOpp = sourceCol ? sourceCol.opportunities.find(o => o.Id === id) : null;
        this.dragSourceStage = sourceCol ? sourceCol.stage : null;
        event.currentTarget.classList.add('dragging');
    }

    handleDragEnter(event) {
        event.preventDefault();
        event.currentTarget.classList.add('drag-over');
    }

    handleDragOver(event) {
        event.preventDefault();
    }

    handleDragLeave(event) {
        if (!event.currentTarget.contains(event.relatedTarget)) {
            event.currentTarget.classList.remove('drag-over');
        }
    }

    handleDrop(event) {
        event.preventDefault();
        const targetStage = event.currentTarget.dataset.stage;
        event.currentTarget.classList.remove('drag-over');

        if (!this.draggedOppId || !targetStage || targetStage === this.dragSourceStage) return;

        const snapshot = JSON.parse(JSON.stringify(this.columns));
        this.columns = this.columns.map(col => {
            if (col.stage === this.dragSourceStage) {
                const opps = col.opportunities.filter(o => o.Id !== this.draggedOppId);
                const total = opps.reduce((s, o) => s + (o.rawAmount || 0), 0);
                return { ...col, opportunities: opps, count: opps.length, totalFormatted: total > 0 ? currencyFormatter.format(total) : null };
            }
            if (col.stage === targetStage) {
                const opps = [...col.opportunities, this.draggedOpp];
                const total = opps.reduce((s, o) => s + (o.rawAmount || 0), 0);
                return { ...col, opportunities: opps, count: opps.length, totalFormatted: total > 0 ? currencyFormatter.format(total) : null };
            }
            return col;
        });

        const oppId = this.draggedOppId;
        this.draggedOppId = null;
        this.draggedOpp = null;
        this.dragSourceStage = null;

        updateOpportunityStage({ oppId, newStage: targetStage })
            .then(() => {
                this.dispatchEvent(new ShowToastEvent({
                    title: 'Stage Updated',
                    message: `Moved to ${targetStage}`,
                    variant: 'success'
                }));
                return refreshApex(this.wiredResult);
            })
            .catch(err => {
                this.columns = snapshot;
                this.dispatchEvent(new ShowToastEvent({
                    title: 'Error',
                    message: err.body ? err.body.message : 'Could not update stage.',
                    variant: 'error'
                }));
            });
    }
}