import { LightningElement, api, wire } from 'lwc';
import getDealersForOpportunity from '@salesforce/apex/OpportunityDashboardController.getDealersForOpportunity';

export default class OpportunityDealers extends LightningElement {
    @api recordId;
    dealers;
    error;

    @wire(getDealersForOpportunity, { oppId: '$recordId' })
    wired({ data, error }) {
        if (data) {
            this.dealers = data.map(d => ({ id: d.id, name: d.name, url: '/' + d.id }));
            this.error = undefined;
        } else if (error) {
            this.error = error;
            this.dealers = undefined;
        }
    }

    get hasDealers() {
        return this.dealers && this.dealers.length > 0;
    }
}
