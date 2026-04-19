import { LightningElement, wire, track } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import getOpportunitiesForList from '@salesforce/apex/OpportunityDashboardController.getOpportunitiesForList';

const CURRENCY = new Intl.NumberFormat('en-US', { style: 'currency', currency: 'USD', maximumFractionDigits: 0 });

const COLUMNS = [
    { label: 'ID',       field: 'uniqueId',      sortable: true  },
    { label: 'Account',  field: 'accountName',   sortable: true  },
    { label: 'Stage',    field: 'StageName',     sortable: true  },
    { label: 'Amount',   field: 'rawAmount',     sortable: true  },
    { label: 'Type',     field: 'Type',          sortable: true  },
    { label: 'Dealer',   field: 'dealerName',    sortable: true  },
    { label: 'Owner',    field: 'ownerName',     sortable: true  },
    { label: 'Days',     field: 'LastStageChangeInDays', sortable: true },
];

function stalenessColor(days) {
    if (days <= 1)  return '#97C459';
    if (days <= 3)  return '#C8D96A';
    if (days <= 6)  return '#EF9F27';
    if (days <= 13) return '#E8804A';
    return '#E24B4A';
}

function mapOpp(opp) {
    const days = opp.LastStageChangeInDays || 0;
    return {
        Id:                    opp.Id,
        url:                   '/' + opp.Id,
        uniqueId:              opp.Unique_ID__c || '—',
        accountName:           opp.Account ? opp.Account.Name : opp.Name,
        StageName:             opp.StageName || '',
        rawAmount:             opp.Amount || 0,
        amountFormatted:       opp.Amount ? CURRENCY.format(opp.Amount) : '—',
        Type:                  opp.Type || '—',
        dealerName:            opp.Dealer__r ? opp.Dealer__r.Name : '—',
        ownerName:             opp.Owner ? opp.Owner.Name : '—',
        LastStageChangeInDays: days,
        daysLabel:             days === 0 ? 'Today' : `${days}d`,
        dotStyle:              `background:${stalenessColor(days)};`,
    };
}

export default class OpportunityList extends NavigationMixin(LightningElement) {
    @track searchTerm   = '';
    @track filterStage  = '';
    @track filterType   = '';
    @track sortField    = 'accountName';
    @track sortAsc      = true;
    @track isLoading    = true;
    @track error;

    _allOpps = [];
    columns  = COLUMNS;

    @wire(getOpportunitiesForList)
    wiredOpps({ data, error }) {
        this.isLoading = false;
        if (data) {
            this._allOpps = data.map(mapOpp);
            this.error    = undefined;
        } else if (error) {
            this.error    = error;
        }
    }

    get rows() {
        const term  = this.searchTerm.toLowerCase();
        const stage = this.filterStage;
        const type  = this.filterType;
        const field = this.sortField;
        const asc   = this.sortAsc;

        let result = this._allOpps;

        if (term) {
            result = result.filter(o =>
                [o.accountName, o.uniqueId, o.StageName, o.ownerName, o.dealerName, o.Type]
                    .some(v => v && v.toLowerCase().includes(term))
            );
        }
        if (stage) result = result.filter(o => o.StageName === stage);
        if (type)  result = result.filter(o => o.Type === type);

        result = [...result].sort((a, b) => {
            const av = a[field] ?? '';
            const bv = b[field] ?? '';
            if (av < bv) return asc ? -1 : 1;
            if (av > bv) return asc ? 1 : -1;
            return 0;
        });

        return result;
    }

    get rowCount() {
        return `${this.rows.length} opportunit${this.rows.length === 1 ? 'y' : 'ies'}`;
    }

    get stageOptions() {
        const stages = [...new Set(this._allOpps.map(o => o.StageName).filter(Boolean))].sort();
        return [{ label: 'All Stages', value: '' }, ...stages.map(s => ({ label: s, value: s }))];
    }

    get typeOptions() {
        const types = [...new Set(this._allOpps.map(o => o.Type).filter(t => t && t !== '—'))].sort();
        return [{ label: 'All Types', value: '' }, ...types.map(t => ({ label: t, value: t }))];
    }

    get headerColumns() {
        return COLUMNS.map(col => ({
            ...col,
            headerClass: 'ol-th' +
                (col.sortable ? ' ol-th-sortable' : '') +
                (this.sortField === col.field ? ' ol-th-active' : ''),
            sortIcon: this.sortField === col.field ? (this.sortAsc ? '▲' : '▼') : '',
        }));
    }

    get isEmpty() {
        return !this.isLoading && !this.error && this.rows.length === 0;
    }

    handleSearch(event) {
        this.searchTerm = event.target.value;
    }

    handleFilterChange(event) {
        const key = event.target.dataset.key;
        if (key === 'stage') this.filterStage = event.target.value;
        if (key === 'type')  this.filterType  = event.target.value;
    }

    handleSort(event) {
        const field = event.currentTarget.dataset.field;
        if (!field) return;
        if (this.sortField === field) {
            this.sortAsc = !this.sortAsc;
        } else {
            this.sortField = field;
            this.sortAsc   = true;
        }
    }

    handleRowClick(event) {
        const id = event.currentTarget.dataset.id;
        if (!id) return;
        this[NavigationMixin.Navigate]({
            type: 'standard__recordPage',
            attributes: { recordId: id, actionName: 'view' },
        });
    }
}
