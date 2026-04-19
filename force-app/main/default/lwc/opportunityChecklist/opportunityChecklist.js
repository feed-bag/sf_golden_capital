import { LightningElement, api, wire, track } from 'lwc';
import { refreshApex } from '@salesforce/apex';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getChecklistItems from '@salesforce/apex/OpportunityChecklistController.getChecklistItems';
import toggleComplete from '@salesforce/apex/OpportunityChecklistController.toggleComplete';
import addItem from '@salesforce/apex/OpportunityChecklistController.addItem';
import deleteItem from '@salesforce/apex/OpportunityChecklistController.deleteItem';
import saveNotes from '@salesforce/apex/OpportunityChecklistController.saveNotes';
import updateDealerVisible from '@salesforce/apex/OpportunityChecklistController.updateDealerVisible';

function timeAgo(dateStr) {
    if (!dateStr) return null;
    const diff = Date.now() - new Date(dateStr).getTime();
    const hours = Math.floor(diff / 3600000);
    if (hours < 1) return 'just now';
    if (hours < 24) return `${hours}h ago`;
    return `${Math.floor(hours / 24)}d ago`;
}

function mapItem(item) {
    return {
        ...item,
        checkClass:              'c-check' + (item.Complete__c       ? ' checked' : ''),
        titleClass:              'c-title' + (item.Complete__c       ? ' done'    : ''),
        trackClass:              'c-track' + (item.Dealer_Visible__c ? ' active'  : ''),
        switchLabelClass:        'c-switch-label' + (item.Dealer_Visible__c  ? ' active' : ''),
        noteLength:              (item.Notes__c || '').length,
        lastModifiedLabel:       item.Notes__c ? timeAgo(item.LastModifiedDate) : null,
    };
}

export default class OpportunityChecklist extends LightningElement {
    @api recordId;

    @track groups = [];
    @track showAddModal = false;
    @track newItemName = '';
    @track newItemDueDate = null;
    @track newItemDealerVisible = false;
    @track newItemTemplateId = null;
    @track isSaving = false;
    @track expandedSections = {};

    isLoading = false;
    error = null;
    wiredResult;

    // Tracks pending (unsaved) note text per item ID — plain object, intentionally not @track
    pendingNotes = {};
    _initializedTextareas = new Set();

    @wire(getChecklistItems, { opportunityId: '$recordId' })
    wiredChecklistItems(result) {
        this.wiredResult = result;
        this.isLoading = false;
        this._initializedTextareas = new Set();
        if (result.data) {
            this.error = null;
            this.groups = result.data.map(group => {
                const isExpanded = this.expandedSections[group.templateId] !== false;
                return {
                    ...group,
                    isExpanded,
                    allComplete: group.totalCount > 0 && group.completeCount === group.totalCount,
                    chevronIcon: isExpanded ? 'utility:chevrondown' : 'utility:chevronright',
                    progressClass: group.completeCount === group.totalCount && group.totalCount > 0
                        ? 'progress-badge progress-complete'
                        : 'progress-badge',
                    items: group.items.map(mapItem)
                };
            });
        } else if (result.error) {
            this.error = result.error;
        }
    }

    renderedCallback() {
        this.template.querySelectorAll('textarea.c-textarea').forEach(ta => {
            const itemId = ta.dataset.itemId;
            if (!this._initializedTextareas.has(itemId)) {
                ta.value = this.pendingNotes[itemId] !== undefined
                    ? this.pendingNotes[itemId]
                    : this._getNoteForItem(itemId);
                this._initializedTextareas.add(itemId);
            }
        });
    }

    _getNoteForItem(itemId) {
        for (const group of this.groups) {
            const item = group.items.find(i => i.Id === itemId);
            if (item) return item.Notes__c || '';
        }
        return '';
    }

    get isEmpty() {
        return !this.isLoading && !this.error && this.groups.length === 0;
    }

    get hasGroups() {
        return !this.isLoading && !this.error && this.groups.length > 0;
    }

    get hasTemplates() {
        return this.groups.some(g => g.templateId != null);
    }

    get templateOptions() {
        const opts = this.groups
            .filter(g => g.templateId != null)
            .map(g => ({ label: g.templateName, value: g.templateId }));
        opts.unshift({ label: 'No Section', value: '' });
        return opts;
    }

    handleToggleSection(event) {
        const templateId = event.currentTarget.dataset.templateId;
        this.groups = this.groups.map(group => {
            if (group.templateId === templateId) {
                const isExpanded = !group.isExpanded;
                this.expandedSections[templateId] = isExpanded;
                return { ...group, isExpanded, chevronIcon: isExpanded ? 'utility:chevrondown' : 'utility:chevronright' };
            }
            return group;
        });
    }

    handleToggleComplete(event) {
        const itemId = event.currentTarget.dataset.itemId;
        const item = this._findItem(itemId);
        if (!item) return;
        const complete = !item.Complete__c;
        this._updateItem(itemId, { Complete__c: complete });
        toggleComplete({ itemId, complete })
            .then(() => refreshApex(this.wiredResult))
            .catch(err => {
                this._updateItem(itemId, { Complete__c: !complete });
                this.showToast('Error', err.body?.message || 'Could not update item.', 'error');
            });
    }

    handleToggleDealerVisible(event) {
        const itemId = event.currentTarget.dataset.itemId;
        const item = this._findItem(itemId);
        if (!item) return;
        const dealerVisible = !item.Dealer_Visible__c;
        this._initializedTextareas.delete(itemId);
        this._updateItem(itemId, { Dealer_Visible__c: dealerVisible });
        updateDealerVisible({ itemId, dealerVisible })
            .then(() => refreshApex(this.wiredResult))
            .catch(err => {
                this._updateItem(itemId, { Dealer_Visible__c: !dealerVisible });
                this.showToast('Error', err.body?.message || 'Could not update visibility.', 'error');
            });
    }

    handleNoteChange(event) {
        const itemId = event.target.dataset.itemId;
        this.pendingNotes[itemId] = event.target.value;
    }

    handleSaveNote(event) {
        const itemId = event.currentTarget.dataset.itemId;
        const notes = this.pendingNotes[itemId] !== undefined
            ? this.pendingNotes[itemId]
            : this._getNoteForItem(itemId);
        saveNotes({ itemId, notes })
            .then(() => {
                delete this.pendingNotes[itemId];
                return refreshApex(this.wiredResult);
            })
            .catch(err => this.showToast('Error', err.body?.message || 'Could not save note.', 'error'));
    }

    handleDeleteItem(event) {
        const itemId = event.currentTarget.dataset.itemId;
        deleteItem({ itemId })
            .then(() => {
                delete this.pendingNotes[itemId];
                return refreshApex(this.wiredResult);
            })
            .catch(err => this.showToast('Error', err.body?.message || 'Could not delete item.', 'error'));
    }

    handleOpenAddModal(event) {
        const templateId = event.currentTarget.dataset.templateId;
        this.newItemTemplateId = templateId || (this.groups[0]?.templateId ?? null);
        this.newItemName = '';
        this.newItemDueDate = null;
        this.newItemDealerVisible = false;
        this.showAddModal = true;
    }

    handleCloseAddModal() { this.showAddModal = false; }

    handleNewItemNameChange(event)         { this.newItemName = event.target.value; }
    handleNewItemDueDateChange(event)      { this.newItemDueDate = event.target.value || null; }
    handleNewItemDealerVisibleChange(event){ this.newItemDealerVisible = event.target.checked; }
    handleNewItemTemplateChange(event)     { this.newItemTemplateId = event.target.value || null; }

    handleSaveNewItem() {
        if (!this.newItemName?.trim()) {
            this.showToast('Validation', 'Item name is required.', 'warning');
            return;
        }
        this.isSaving = true;
        addItem({
            opportunityId: this.recordId,
            templateId: this.newItemTemplateId || null,
            name: this.newItemName.trim(),
            dueDate: this.newItemDueDate || null,
            dealerVisible: this.newItemDealerVisible
        })
            .then(() => {
                this.showAddModal = false;
                this.isSaving = false;
                return refreshApex(this.wiredResult);
            })
            .catch(err => {
                this.isSaving = false;
                this.showToast('Error', err.body?.message || 'Could not add item.', 'error');
            });
    }

    _findItem(itemId) {
        for (const group of this.groups) {
            const item = group.items.find(i => i.Id === itemId);
            if (item) return item;
        }
        return null;
    }

    _updateItem(itemId, changes) {
        this.groups = this.groups.map(group => ({
            ...group,
            items: group.items.map(item => {
                if (item.Id !== itemId) return item;
                return mapItem({ ...item, ...changes });
            })
        }));
    }

    showToast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }
}
