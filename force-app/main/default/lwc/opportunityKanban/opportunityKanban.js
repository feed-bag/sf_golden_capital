import { LightningElement, wire, track } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { refreshApex } from '@salesforce/apex';
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

const STAGE_META = {
    'App In':               { color: '#85B7EB', progress: 8 },
    'Sales Follow Up':      { color: '#9BB5E0', progress: 17 },
    'On Hold':              { color: '#A0A0B8', progress: 25 },
    'Internal Review':      { color: '#AFA9EC', progress: 33 },
    'Submitted':            { color: '#C4A8E8', progress: 42 },
    'Approved':             { color: '#F0C97B', progress: 50 },
    'Pre Docs':             { color: '#F0997B', progress: 58 },
    'Docs Requested':       { color: '#F08B6B', progress: 67 },
    'Docs Out':             { color: '#EDB96A', progress: 75 },
    'Funding Request Sent': { color: '#C8D96A', progress: 83 },
    'Funded':               { color: '#A8CC5A', progress: 92 },
    'FPC':                  { color: '#97C459', progress: 100 }
};

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

function daysAgo(dateStr) {
    const ms = Date.now() - new Date(dateStr).getTime();
    return Math.floor(ms / (1000 * 60 * 60 * 24));
}

export default class OpportunityKanban extends LightningElement {
    @track columns;
    @track isLoading = true;
    @track error;
    draggedOppId;
    wiredResult;

    @wire(getOpenOpportunities)
    wiredOpportunities(result) {
        this.wiredResult = result;
        this.isLoading = false;
        if (result.data) {
            this.error = undefined;
            this.buildColumns(result.data);
        } else if (result.error) {
            this.error = result.error;
            this.columns = undefined;
        }
    }

    buildColumns(opportunities) {
        const map = {};
        STAGES.forEach(stage => { map[stage] = []; });

        opportunities.forEach(opp => {
            if (map[opp.StageName] === undefined) return;

            const meta = STAGE_META[opp.StageName] || { color: '#cccccc', progress: 0 };
            const ownerName = opp.Owner ? opp.Owner.Name : '';
            const palette = AVATAR_PALETTES[hashIndex(ownerName, AVATAR_PALETTES.length)];
            const days = daysAgo(opp.LastModifiedDate);
            const dotColor = days < 7 ? '#639922' : days <= 14 ? '#EF9F27' : '#E24B4A';

            const tags = [];
            if (opp.Type)      tags.push({ key: 'type',   label: opp.Type,            tagClass: 'kb-tag kb-tag-blue' });
            if (opp.Dealer__r) tags.push({ key: 'dealer', label: opp.Dealer__r.Name,  tagClass: 'kb-tag kb-tag-neutral' });

            map[opp.StageName].push({
                Id: opp.Id,
                url: '/' + opp.Id,
                accountName: opp.Account ? opp.Account.Name : opp.Name,
                uniqueId: opp.Unique_ID__c || '',
                tags,
                amountFormatted: opp.Amount ? currencyFormatter.format(opp.Amount) : null,
                stageStripStyle: `background:${meta.color};`,
                progressFillStyle: `width:${meta.progress}%; background:${meta.color};`,
                progressPct: meta.progress + '%',
                ownerInitials: getInitials(ownerName),
                ownerName,
                ownerAvatarStyle: `background:${palette.bg}; color:${palette.fg};`,
                daysAgoLabel: days === 0 ? 'Today' : days === 1 ? '1d ago' : `${days}d ago`,
                dotStyle: `background:${dotColor};`
            });
        });

        this.columns = STAGES.map(stage => ({
            stage,
            opportunities: map[stage],
            count: map[stage].length
        }));
    }

    handleDragStart(event) {
        this.draggedOppId = event.currentTarget.dataset.id;
    }

    handleDragOver(event) {
        event.preventDefault();
        event.currentTarget.classList.add('drag-over');
    }

    handleDragLeave(event) {
        event.currentTarget.classList.remove('drag-over');
    }

    handleDrop(event) {
        event.preventDefault();
        const targetStage = event.currentTarget.dataset.stage;
        event.currentTarget.classList.remove('drag-over');

        if (!this.draggedOppId || !targetStage) return;

        const currentColumn = this.columns.find(col =>
            col.opportunities.some(opp => opp.Id === this.draggedOppId)
        );
        if (currentColumn && currentColumn.stage === targetStage) return;

        updateOpportunityStage({ oppId: this.draggedOppId, newStage: targetStage })
            .then(() => {
                this.dispatchEvent(new ShowToastEvent({
                    title: 'Stage Updated',
                    message: `Moved to ${targetStage}`,
                    variant: 'success'
                }));
                return refreshApex(this.wiredResult);
            })
            .catch(err => {
                this.dispatchEvent(new ShowToastEvent({
                    title: 'Error',
                    message: err.body ? err.body.message : 'Could not update stage.',
                    variant: 'error'
                }));
            });

        this.draggedOppId = null;
    }
}
