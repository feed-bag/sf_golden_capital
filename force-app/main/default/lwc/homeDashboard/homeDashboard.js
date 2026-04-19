import { LightningElement, track } from 'lwc';

export default class HomeDashboard extends LightningElement {
    @track activeTab = 'pipeline';

    get isPipeline() { return this.activeTab === 'pipeline'; }
    get isMetrics()  { return this.activeTab === 'metrics'; }
    get isListView() { return this.activeTab === 'list'; }

    get pipelineTabClass() {
        return 'hd-tab' + (this.activeTab === 'pipeline' ? ' hd-tab-active' : '');
    }
    get metricsTabClass() {
        return 'hd-tab' + (this.activeTab === 'metrics' ? ' hd-tab-active' : '');
    }
    get listTabClass() {
        return 'hd-tab' + (this.activeTab === 'list' ? ' hd-tab-active' : '');
    }

    handleTabClick(evt) {
        this.activeTab = evt.currentTarget.dataset.tab;
    }
}
