import { LightningElement, api, wire, track } from 'lwc';
import { refreshApex } from '@salesforce/apex';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getChecklistItems from '@salesforce/apex/OpportunityChecklistController.getChecklistItems';
import toggleComplete from '@salesforce/apex/OpportunityChecklistController.toggleComplete';
import addItem from '@salesforce/apex/OpportunityChecklistController.addItem';
import deleteItem from '@salesforce/apex/OpportunityChecklistController.deleteItem';

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

    @wire(getChecklistItems, { opportunityId: '$recordId' })
    wiredChecklistItems(result) {
        this.wiredResult = result;
        this.isLoading = false;
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
                    items: group.items.map(item => ({
                        ...item,
                        formattedDueDate: item.Due_Date__c
                            ? new Date(item.Due_Date__c + 'T00:00:00').toLocaleDateString()
                            : null,
                        dueDateClass: this.getDueDateClass(item.Due_Date__c)
                    }))
                };
            });
        } else if (result.error) {
            this.error = result.error;
        }
    }

    getDueDateClass(dueDate) {
        if (!dueDate) return 'due-date';
        const today = new Date();
        today.setHours(0, 0, 0, 0);
        const due = new Date(dueDate + 'T00:00:00');
        if (due < today) return 'due-date due-overdue';
        if (due.getTime() === today.getTime()) return 'due-date due-today';
        return 'due-date';
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
                return {
                    ...group,
                    isExpanded,
                    chevronIcon: isExpanded ? 'utility:chevrondown' : 'utility:chevronright'
                };
            }
            return group;
        });
    }

    handleToggleComplete(event) {
        const itemId = event.target.dataset.itemId;
        const complete = event.target.checked;
        toggleComplete({ itemId, complete })
            .then(() => refreshApex(this.wiredResult))
            .catch(error => {
                this.showToast('Error', error.body?.message || 'Could not update item.', 'error');
                refreshApex(this.wiredResult);
            });
    }

    handleDeleteItem(event) {
        const itemId = event.currentTarget.dataset.itemId;
        deleteItem({ itemId })
            .then(() => {
                this.showToast('Deleted', 'Checklist item removed.', 'success');
                return refreshApex(this.wiredResult);
            })
            .catch(error => {
                this.showToast('Error', error.body?.message || 'Could not delete item.', 'error');
            });
    }

    handleOpenAddModal(event) {
        const templateId = event.currentTarget.dataset.templateId;
        this.newItemTemplateId = templateId || (this.groups[0]?.templateId ?? null);
        this.newItemName = '';
        this.newItemDueDate = null;
        this.newItemDealerVisible = false;
        this.showAddModal = true;
    }

    handleCloseAddModal() {
        this.showAddModal = false;
    }

    handleNewItemNameChange(event) {
        this.newItemName = event.target.value;
    }

    handleNewItemDueDateChange(event) {
        this.newItemDueDate = event.target.value || null;
    }

    handleNewItemDealerVisibleChange(event) {
        this.newItemDealerVisible = event.target.checked;
    }

    handleNewItemTemplateChange(event) {
        this.newItemTemplateId = event.target.value || null;
    }

    handleSaveNewItem() {
        if (!this.newItemName || this.newItemName.trim() === '') {
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
                this.showToast('Added', 'Checklist item added.', 'success');
                return refreshApex(this.wiredResult);
            })
            .catch(error => {
                this.isSaving = false;
                this.showToast('Error', error.body?.message || 'Could not add item.', 'error');
            });
    }

    showToast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }
}
