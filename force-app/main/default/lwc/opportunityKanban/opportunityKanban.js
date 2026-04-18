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

const STAGE_PROGRESS = {
    'App In': 8, 'Sales Follow Up': 17, 'On Hold': 25,
    'Internal Review': 33, 'Submitted': 42, 'Approved': 50,
    'Pre Docs': 58, 'Docs Requested': 67, 'Docs Out': 75,
    'Funding Request Sent': 83, 'Funded': 92, 'FPC': 100
};

function stalenessColor(days) {
    if (days <= 1)  return '#97C459'; // green
    if (days <= 3)  return '#C8D96A'; // yellow-green
    if (days <= 6)  return '#EF9F27'; // amber
    if (days <= 13) return '#E8804A'; // orange
    return '#E24B4A';                 // red
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

            const daysInStage = opp.LastStageChangeInDays || 0;
            const staleColor = stalenessColor(daysInStage);
            const progress = STAGE_PROGRESS[opp.StageName] || 0;
            const ownerName = opp.Owner ? opp.Owner.Name : '';
            const palette = AVATAR_PALETTES[hashIndex(ownerName, AVATAR_PALETTES.length)];

            const tags = [];
            if (opp.Type)      tags.push({ key: 'type',   label: opp.Type,            tagClass: 'kb-tag kb-tag-blue' });
            if (opp.Dealer__r) tags.push({ key: 'dealer', label: opp.Dealer__r.Name,  tagClass: 'kb-tag kb-tag-neutral' });

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
                daysInStageLabel: daysInStage === 0 ? 'Today' : daysInStage === 1 ? '1d in stage' : `${daysInStage}d in stage`,
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
