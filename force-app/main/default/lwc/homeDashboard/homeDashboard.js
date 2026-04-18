import { LightningElement, track } from 'lwc';

export default class HomeDashboard extends LightningElement {
    @track activeTab = 'pipeline';

    get isPipeline() { return this.activeTab === 'pipeline'; }
    get isMetrics()  { return this.activeTab === 'metrics'; }

    get pipelineTabClass() {
        return 'hd-tab' + (this.activeTab === 'pipeline' ? ' hd-tab-active' : '');
    }
    get metricsTabClass() {
        return 'hd-tab' + (this.activeTab === 'metrics' ? ' hd-tab-active' : '');
    }

    handleTabClick(evt) {
        this.activeTab = evt.currentTarget.dataset.tab;
    }
}
