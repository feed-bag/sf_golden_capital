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

const formatter = new Intl.NumberFormat('en-US', {
    style: 'currency',
    currency: 'USD',
    maximumFractionDigits: 0
});

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
        STAGES.forEach(stage => {
            map[stage] = [];
        });

        opportunities.forEach(opp => {
            if (map[opp.StageName] !== undefined) {
                map[opp.StageName].push({
                    Id: opp.Id,
                    Name: opp.Name,
                    accountName: opp.Account ? opp.Account.Name : '',
                    amountFormatted: opp.Amount ? formatter.format(opp.Amount) : null,
                    url: '/' + opp.Id
                });
            }
        });

        this.columns = STAGES.map(stage => ({
            stage,
            opportunities: map[stage],
            count: map[stage].length
        }));
    }

    handleDragStart(event) {
        this.draggedOppId = event.currentTarget.dataset.id;
        event.currentTarget.classList.add('dragging');
    }

    handleDragOver(event) {
        event.preventDefault();
        event.currentTarget.classList.add('drag-over');
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
            .catch(error => {
                this.dispatchEvent(new ShowToastEvent({
                    title: 'Error',
                    message: error.body ? error.body.message : 'Could not update stage.',
                    variant: 'error'
                }));
            });

        this.draggedOppId = null;
    }
}
