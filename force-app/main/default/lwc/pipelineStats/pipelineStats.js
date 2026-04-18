import { LightningElement, wire } from 'lwc';
import getPipelineStats from '@salesforce/apex/OpportunityDashboardController.getPipelineStats';

export default class PipelineStats extends LightningElement {
    stats;
    error;

    @wire(getPipelineStats)
    wiredStats({ data, error }) {
        if (data) {
            this.stats = data;
            this.error = undefined;
        } else if (error) {
            this.error = error;
            this.stats = undefined;
        }
    }

    get volumeFundedFormatted() {
        if (!this.stats) return '$0';
        const val = this.stats.volumeFundedThisMonth || 0;
        return new Intl.NumberFormat('en-US', {
            style: 'currency',
            currency: 'USD',
            maximumFractionDigits: 0
        }).format(val);
    }
}
