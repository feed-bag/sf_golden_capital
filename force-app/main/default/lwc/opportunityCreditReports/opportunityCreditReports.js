import { LightningElement, api, wire } from 'lwc';
import getCreditReportsForOpportunity from '@salesforce/apex/OpportunityDashboardController.getCreditReportsForOpportunity';

const COLUMNS = [
    {
        label: 'Name',
        fieldName: 'recordUrl',
        type: 'url',
        typeAttributes: { label: { fieldName: 'name' }, target: '_top' },
        sortable: true
    },
    {
        label: 'Created Date',
        fieldName: 'createdDate',
        type: 'date',
        typeAttributes: { year: 'numeric', month: 'short', day: '2-digit' },
        sortable: true
    },
    {
        label: 'Contact',
        fieldName: 'contactUrl',
        type: 'url',
        typeAttributes: { label: { fieldName: 'contactName' }, target: '_top' },
        sortable: true
    },
    { label: 'Score', fieldName: 'score', type: 'number', sortable: true, cellAttributes: { alignment: 'left' } },
    { label: 'Open Tradelines', fieldName: 'openTradelines', type: 'number', sortable: true, cellAttributes: { alignment: 'left' } },
    { label: 'Closed Tradelines', fieldName: 'closedTradelines', type: 'number', sortable: true, cellAttributes: { alignment: 'left' } },
    { label: 'Collections', fieldName: 'collections', type: 'number', sortable: true, cellAttributes: { alignment: 'left' } },
    { label: 'Public Records', fieldName: 'publicRecords', type: 'number', sortable: true, cellAttributes: { alignment: 'left' } }
];

export default class OpportunityCreditReports extends LightningElement {
    @api recordId;
    columns = COLUMNS;
    rows;
    error;
    sortedBy = 'createdDate';
    sortedDirection = 'desc';

    @wire(getCreditReportsForOpportunity, { oppId: '$recordId' })
    wired({ data, error }) {
        if (data) {
            this.rows = data;
            this.error = undefined;
        } else if (error) {
            this.error = error;
            this.rows = undefined;
        }
    }

    get hasRows() {
        return this.rows && this.rows.length > 0;
    }

    handleSort(event) {
        const { fieldName, sortDirection } = event.detail;
        // For URL columns, sort by the displayed label rather than the URL value.
        const labelField = fieldName === 'recordUrl' ? 'name'
                         : fieldName === 'contactUrl' ? 'contactName'
                         : fieldName;
        const dir = sortDirection === 'asc' ? 1 : -1;
        const sorted = [...this.rows].sort((a, b) => {
            const av = a[labelField];
            const bv = b[labelField];
            if (av == null && bv == null) return 0;
            if (av == null) return 1;
            if (bv == null) return -1;
            if (av < bv) return -1 * dir;
            if (av > bv) return 1 * dir;
            return 0;
        });
        this.rows = sorted;
        this.sortedBy = fieldName;
        this.sortedDirection = sortDirection;
    }
}
