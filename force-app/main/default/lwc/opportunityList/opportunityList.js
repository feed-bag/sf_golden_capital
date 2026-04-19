import { LightningElement, wire, track } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { refreshApex } from '@salesforce/apex';
import getOpportunitiesForList  from '@salesforce/apex/OpportunityDashboardController.getOpportunitiesForList';
import getOpportunityFieldMeta  from '@salesforce/apex/OpportunityDashboardController.getOpportunityFieldMeta';
import getActiveUsers           from '@salesforce/apex/OpportunityDashboardController.getActiveUsers';
import bulkUpdateStage          from '@salesforce/apex/OpportunityDashboardController.bulkUpdateStage';
import bulkUpdateOwner          from '@salesforce/apex/OpportunityDashboardController.bulkUpdateOwner';
import bulkDeleteOpportunities  from '@salesforce/apex/OpportunityDashboardController.bulkDeleteOpportunities';

// ── Formatters ────────────────────────────────────────────────────────────────
const CURRENCY = new Intl.NumberFormat('en-US', { style: 'currency', currency: 'USD', maximumFractionDigits: 0 });
const DATE_FMT  = new Intl.DateTimeFormat('en-US', { month: 'short', day: 'numeric', year: 'numeric' });
const LS_KEY    = 'gc_opp_list_cols_v2';

function fmtDate(d) {
    try { return d ? DATE_FMT.format(new Date(d.replace ? d.replace(/-/g, '/') : d)) : '—'; } catch(e) { return '—'; }
}

function formatFieldValue(raw, type) {
    if (raw === null || raw === undefined || raw === '') return '—';
    switch (type) {
        case 'CURRENCY': return CURRENCY.format(Number(raw));
        case 'DATE':     return fmtDate(String(raw));
        case 'DATETIME': return fmtDate(String(raw));
        case 'BOOLEAN':  return raw ? '✓' : '';
        case 'PERCENT':  return `${raw}%`;
        case 'DOUBLE':
        case 'INTEGER':
        case 'LONG':     return raw.toLocaleString();
        default:         return String(raw);
    }
}

// ── Core columns (always available, have special display logic) ───────────────
// Virtual apiNames (accountName / dealerName / ownerName) resolve relationship fields.
const CORE_COLUMNS = [
    { apiName: 'Unique_ID__c',          label: 'ID',           type: 'TEXT',     defaultOn: true  },
    { apiName: 'accountName',           label: 'Account',      type: 'TEXT',     defaultOn: true  },
    { apiName: 'StageName',             label: 'Stage',        type: 'PICKLIST', defaultOn: true  },
    { apiName: 'Amount',                label: 'Amount',       type: 'CURRENCY', defaultOn: true  },
    { apiName: 'Type',                  label: 'Type',         type: 'PICKLIST', defaultOn: true  },
    { apiName: 'dealerName',            label: 'Dealer',       type: 'TEXT',     defaultOn: true  },
    { apiName: 'ownerName',             label: 'Owner',        type: 'TEXT',     defaultOn: true  },
    { apiName: 'LastStageChangeInDays', label: 'Days',         type: 'INTEGER',  defaultOn: true  },
    { apiName: 'CloseDate',             label: 'Close Date',   type: 'DATE',     defaultOn: false },
    { apiName: 'CreatedDate',           label: 'Created',      type: 'DATETIME', defaultOn: false },
];
const CORE_API_SET = new Set(CORE_COLUMNS.map(c => c.apiName));
const DEFAULT_COLS = new Set(CORE_COLUMNS.filter(c => c.defaultOn).map(c => c.apiName));

// ── Stage / type badge colors ─────────────────────────────────────────────────
const STAGE_COLOR_MAP = {
    'Prospecting':    { bg: '#dbeafe', fg: '#1d4ed8' },
    'Qualification':  { bg: '#e0e7ff', fg: '#3730a3' },
    'Needs Analysis': { bg: '#fef9c3', fg: '#854d0e' },
    'Proposal':       { bg: '#ffedd5', fg: '#9a3412' },
    'Negotiation':    { bg: '#fce7f3', fg: '#9d174d' },
    'Application':    { bg: '#e0f2fe', fg: '#0369a1' },
    'Underwriting':   { bg: '#fef3c7', fg: '#92400e' },
    'Approved':       { bg: '#d1fae5', fg: '#065f46' },
    'Funded':         { bg: '#bbf7d0', fg: '#14532d' },
    'FPC':            { bg: '#a7f3d0', fg: '#064e3b' },
    'Fully Funded':   { bg: '#6ee7b7', fg: '#064e3b' },
    'Closed Won':     { bg: '#d1fae5', fg: '#065f46' },
    'Closed Lost':    { bg: '#fee2e2', fg: '#991b1b' },
};
const STAGE_FALLBACK = [
    { bg: '#dbeafe', fg: '#1d4ed8' }, { bg: '#fef3c7', fg: '#92400e' },
    { bg: '#ede9fe', fg: '#5b21b6' }, { bg: '#d1fae5', fg: '#065f46' },
    { bg: '#ffedd5', fg: '#9a3412' }, { bg: '#e0f2fe', fg: '#0369a1' },
    { bg: '#fce7f3', fg: '#9d174d' },
];
const TYPE_COLOR_MAP = {
    'Equipment':       { bg: 'rgba(210,154,46,0.18)', fg: '#7a5200' },
    'Working Capital': { bg: 'rgba(37,53,81,0.12)',   fg: '#1a2d4d' },
    'New Business':    { bg: 'rgba(100,149,237,0.18)',fg: '#1a3a6b' },
};
const TYPE_FALLBACK = [
    { bg: '#ede9fe', fg: '#5b21b6' }, { bg: '#fce7f3', fg: '#9d174d' },
    { bg: '#e0f2fe', fg: '#0369a1' }, { bg: '#f0fdf4', fg: '#166534' },
];

function hashStr(s) {
    let h = 0;
    for (let i = 0; i < s.length; i++) h = ((h * 31) + s.charCodeAt(i)) & 0xffff;
    return h;
}
function stageBadgeStyle(name) {
    const c = STAGE_COLOR_MAP[name] || STAGE_FALLBACK[hashStr(name || '') % STAGE_FALLBACK.length];
    return `background:${c.bg};color:${c.fg};`;
}
function typeBadgeStyle(name) {
    if (!name || name === '—') return null;
    const c = TYPE_COLOR_MAP[name] || TYPE_FALLBACK[hashStr(name) % TYPE_FALLBACK.length];
    return `background:${c.bg};color:${c.fg};`;
}
function stalenessColor(days) {
    if (days <= 1)  return '#97C459';
    if (days <= 3)  return '#C8D96A';
    if (days <= 6)  return '#EF9F27';
    if (days <= 13) return '#E8804A';
    return '#E24B4A';
}

// ── Row mapper — keeps a _raw reference for dynamic field access ──────────────
function mapOpp(opp) {
    const days  = opp.LastStageChangeInDays || 0;
    return {
        Id:                    opp.Id,
        _raw:                  opp,
        // Pre-computed values for core columns (fast access in sort + cells)
        Unique_ID__c:          opp.Unique_ID__c  || '—',
        accountName:           opp.Account ? opp.Account.Name : (opp.Name || '—'),
        StageName:             opp.StageName    || '',
        Amount:                opp.Amount       || 0,
        amountFormatted:       opp.Amount ? CURRENCY.format(opp.Amount) : '—',
        Type:                  opp.Type         || '—',
        dealerName:            opp.Dealer__r    ? opp.Dealer__r.Name : '—',
        ownerName:             opp.Owner        ? opp.Owner.Name     : '—',
        LastStageChangeInDays: days,
        daysLabel:             days === 0 ? 'Today' : `${days}d`,
        dotStyle:              `background:${stalenessColor(days)};`,
        stageStyle:            stageBadgeStyle(opp.StageName || ''),
        typeBadgeStyle:        typeBadgeStyle(opp.Type || '—'),
        showTypeBadge:         !!(opp.Type && opp.Type !== '—'),
        CloseDate:             opp.CloseDate    || '',
        CreatedDate:           opp.CreatedDate  || '',
        closeDateLabel:        fmtDate(opp.CloseDate),
        createdDateLabel:      fmtDate(opp.CreatedDate),
    };
}

// Get the sort-key value for a field (raw/numeric where possible)
function sortValue(row, apiName) {
    switch (apiName) {
        case 'accountName':
        case 'dealerName':
        case 'ownerName':
        case 'Unique_ID__c':
        case 'StageName':
        case 'Amount':
        case 'Type':
        case 'LastStageChangeInDays':
        case 'CloseDate':
        case 'CreatedDate':
            return row[apiName] ?? '';
        default:
            return row._raw ? (row._raw[apiName] ?? '') : '';
    }
}

// Build a lightweight cell descriptor — no DOM, just data
function makeCell(row, col) {
    const api = col.apiName;

    if (api === 'LastStageChangeInDays') {
        return { field: api, value: row.daysLabel, tdClass: 'ol-td ol-td-days',
                 isDot: true, dotStyle: row.dotStyle, isBadge: false, badgeStyle: null };
    }
    if (api === 'StageName') {
        return { field: api, value: row.StageName, tdClass: 'ol-td',
                 isDot: false, dotStyle: null, isBadge: true, badgeStyle: row.stageStyle };
    }
    if (api === 'Type') {
        const badge = row.showTypeBadge;
        return { field: api, value: row.Type, tdClass: 'ol-td',
                 isDot: false, dotStyle: null, isBadge: badge, badgeStyle: badge ? row.typeBadgeStyle : null };
    }
    if (api === 'Amount') {
        return { field: api, value: row.amountFormatted, tdClass: 'ol-td ol-td-amount',
                 isDot: false, dotStyle: null, isBadge: false, badgeStyle: null };
    }
    if (api === 'CloseDate') {
        return { field: api, value: row.closeDateLabel, tdClass: 'ol-td',
                 isDot: false, dotStyle: null, isBadge: false, badgeStyle: null };
    }
    if (api === 'CreatedDate') {
        return { field: api, value: row.createdDateLabel, tdClass: 'ol-td',
                 isDot: false, dotStyle: null, isBadge: false, badgeStyle: null };
    }
    if (CORE_API_SET.has(api)) {
        // Other core columns (accountName, dealerName, ownerName, Unique_ID__c)
        return { field: api, value: row[api] ?? '—', tdClass: 'ol-td',
                 isDot: false, dotStyle: null, isBadge: false, badgeStyle: null };
    }

    // Dynamic column — access via _raw
    const raw = row._raw ? row._raw[api] : null;
    const formatted = formatFieldValue(raw, col.type);
    const isNumeric  = col.type === 'CURRENCY' || col.type === 'DOUBLE'
                     || col.type === 'INTEGER'  || col.type === 'LONG';
    return { field: api, value: formatted,
             tdClass: 'ol-td' + (isNumeric ? ' ol-td-amount' : ''),
             isDot: false, dotStyle: null, isBadge: false, badgeStyle: null };
}

// ── Component ─────────────────────────────────────────────────────────────────
export default class OpportunityList extends NavigationMixin(LightningElement) {
    @track searchTerm  = '';
    @track filterStage = '';
    @track filterType  = '';
    @track sortField   = 'accountName';
    @track sortAsc     = true;
    @track isLoading   = true;
    @track error;

    // Selection
    @track _selectedMap = {};

    // Column picker
    @track _visibleCols  = new Set(DEFAULT_COLS);
    @track _dynamicCols  = [];   // populated when getOpportunityFieldMeta resolves
    @track showColPicker = false;
    @track _colFilter    = '';

    // Modals
    @track showStageModal  = false;
    @track showOwnerModal  = false;
    @track showDeleteModal = false;
    @track _modalStage = '';
    @track _modalOwner = '';
    @track _userFilter = '';
    @track isSaving    = false;

    _allOpps = [];
    _users   = [];
    _wiredOppsResult;

    connectedCallback() {
        try {
            const saved = JSON.parse(localStorage.getItem(LS_KEY));
            if (Array.isArray(saved) && saved.length > 0) {
                this._visibleCols = new Set(saved);
            }
        } catch(e) { /* ignore */ }
    }

    @wire(getOpportunitiesForList)
    wiredOpps(result) {
        this._wiredOppsResult = result;
        this.isLoading = false;
        const { data, error } = result;
        if (data) {
            this._allOpps = data.map(mapOpp);
            this.error    = undefined;
        } else if (error) {
            this.error = error;
        }
    }

    // Field metadata wire — populates extra columns in picker once on load
    @wire(getOpportunityFieldMeta)
    wiredFieldMeta({ data }) {
        if (!data) return;
        // Filter out anything already covered by core columns
        this._dynamicCols = data
            .filter(f => !CORE_API_SET.has(f.apiName))
            .sort((a, b) => a.label.localeCompare(b.label));
    }

    @wire(getActiveUsers)
    wiredUsers({ data }) {
        if (data) this._users = data;
    }

    // ── All available columns (core + dynamic) ────────────────────────────────
    get _allColumns() {
        return [...CORE_COLUMNS, ...this._dynamicCols];
    }

    // ── Visible columns with sort decorations (drives header + cell rendering) ─
    get visibleColumns() {
        const vis  = this._visibleCols;
        const sort = this.sortField;
        const asc  = this.sortAsc;
        return this._allColumns
            .filter(c => vis.has(c.apiName))
            .map(c => ({
                ...c,
                thClass:  'ol-th ol-th-sortable' + (sort === c.apiName ? ' ol-th-active' : ''),
                sortIcon: sort === c.apiName ? (asc ? '▲' : '▼') : '',
            }));
    }

    // ── Rows ──────────────────────────────────────────────────────────────────
    get rows() {
        const term  = this.searchTerm.toLowerCase();
        const stage = this.filterStage;
        const type  = this.filterType;
        const field = this.sortField;
        const asc   = this.sortAsc;

        let result = this._allOpps;

        if (term) {
            result = result.filter(o =>
                [o.accountName, o.Unique_ID__c, o.StageName, o.ownerName, o.dealerName, o.Type]
                    .some(v => v && v.toLowerCase().includes(term))
            );
        }
        if (stage) result = result.filter(o => o.StageName === stage);
        if (type)  result = result.filter(o => o.Type === type);

        result = [...result].sort((a, b) => {
            const av = sortValue(a, field);
            const bv = sortValue(b, field);
            if (av < bv) return asc ? -1 : 1;
            if (av > bv) return asc ? 1 : -1;
            return 0;
        });

        return result;
    }

    // Cells are computed once per render cycle per visible-column set.
    // Kept separate from selection so a checkbox toggle only re-maps isSelected/rowClass,
    // not the cell content.
    get _rowsWithCells() {
        const visCols = this.visibleColumns;
        return this.rows.map(r => ({
            Id:    r.Id,
            cells: visCols.map(col => makeCell(r, col)),
        }));
    }

    get rowsWithSelection() {
        const sel   = this._selectedMap;
        return this._rowsWithCells.map(r => ({
            ...r,
            isSelected: !!sel[r.Id],
            rowClass: 'ol-row' + (sel[r.Id] ? ' ol-row-selected' : ''),
        }));
    }

    // ── Selection ─────────────────────────────────────────────────────────────
    get selectedIds()    { return Object.keys(this._selectedMap).filter(k => this._selectedMap[k]); }
    get selectionCount() { return this.selectedIds.length; }
    get hasSelection()   { return this.selectionCount > 0; }

    get selectionLabel() {
        const n = this.selectionCount;
        return `${n} record${n === 1 ? '' : 's'} selected`;
    }

    get allSelected() {
        const rows = this.rows;
        return rows.length > 0 && rows.every(r => this._selectedMap[r.Id]);
    }

    get isIndeterminate() {
        const n = this.selectionCount;
        return n > 0 && n < this.rows.length;
    }

    renderedCallback() {
        const cb = this.template.querySelector('.ol-th-check input[type="checkbox"]');
        if (cb) cb.indeterminate = this.isIndeterminate;
    }

    handleSelectAll(event) {
        const checked = event.target.checked;
        const map = { ...this._selectedMap };
        this.rows.forEach(r => { if (checked) map[r.Id] = true; else delete map[r.Id]; });
        this._selectedMap = map;
    }

    handleSelectRow(event) {
        event.stopPropagation();
        const id = event.target.dataset.id; const checked = event.target.checked;
        const map = { ...this._selectedMap };
        if (checked) map[id] = true; else delete map[id];
        this._selectedMap = map;
    }

    handleCheckCellClick(event) { event.stopPropagation(); }
    handleClearSelection()      { this._selectedMap = {}; }

    // ── Column picker ─────────────────────────────────────────────────────────
    get colPickerOptions() {
        const vis    = this._visibleCols;
        const filter = this._colFilter.toLowerCase();
        return this._allColumns
            .filter(c => !filter || c.label.toLowerCase().includes(filter))
            .map(c => ({ apiName: c.apiName, label: c.label, checked: vis.has(c.apiName) }));
    }

    get colBtnClass() {
        return 'ol-col-btn' + (this.showColPicker ? ' ol-col-btn-active' : '');
    }

    handleToggleColPicker(event) {
        event.stopPropagation();
        this.showColPicker = !this.showColPicker;
        if (this.showColPicker) this._colFilter = '';
    }

    handleColPickerPanelClick(event) { event.stopPropagation(); }
    handleCloseColPicker()           { this.showColPicker = false; }

    handleColFilter(event) { this._colFilter = event.target.value; }

    handleColToggle(event) {
        event.stopPropagation();
        const field   = event.target.dataset.field;
        const checked = event.target.checked;
        const cols    = new Set(this._visibleCols);
        if (checked) cols.add(field);
        else if (cols.size > 1) cols.delete(field);
        this._visibleCols = cols;
        try { localStorage.setItem(LS_KEY, JSON.stringify([...cols])); } catch(e) { /* ignore */ }
    }

    // ── Toolbar ───────────────────────────────────────────────────────────────
    get rowCount() {
        return `${this.rows.length} opportunit${this.rows.length === 1 ? 'y' : 'ies'}`;
    }

    get stageOptions() {
        const stages = [...new Set(this._allOpps.map(o => o.StageName).filter(Boolean))].sort();
        return [{ label: 'All Stages', value: '' }, ...stages.map(s => ({ label: s, value: s }))];
    }

    get stageSelectOptions() { return this.stageOptions.filter(o => o.value !== ''); }

    get typeOptions() {
        const types = [...new Set(this._allOpps.map(o => o.Type).filter(t => t && t !== '—'))].sort();
        return [{ label: 'All Types', value: '' }, ...types.map(t => ({ label: t, value: t }))];
    }

    get isEmpty() { return !this.isLoading && !this.error && this.rows.length === 0; }

    handleSearch(event)       { this.searchTerm = event.target.value; }

    handleFilterChange(event) {
        const key = event.target.dataset.key;
        if (key === 'stage') this.filterStage = event.target.value;
        if (key === 'type')  this.filterType  = event.target.value;
    }

    handleSort(event) {
        const field = event.currentTarget.dataset.field;
        if (!field) return;
        if (this.sortField === field) { this.sortAsc = !this.sortAsc; }
        else { this.sortField = field; this.sortAsc = true; }
    }

    handleRowClick(event) {
        const id = event.currentTarget.dataset.id;
        if (!id) return;
        this[NavigationMixin.Navigate]({
            type: 'standard__recordPage',
            attributes: { recordId: id, actionName: 'view' },
        });
    }

    // ── Bulk: Change Stage ────────────────────────────────────────────────────
    handleBulkStage() {
        this._modalStage    = this.stageSelectOptions[0]?.value || '';
        this.showStageModal = true;
    }
    handleModalStageChange(event) { this._modalStage = event.target.value; }

    async handleStageApply() {
        const ids = [...this.selectedIds]; const count = ids.length;
        this.isSaving = true;
        try {
            await bulkUpdateStage({ oppIds: ids, stageName: this._modalStage });
            await refreshApex(this._wiredOppsResult);
            this._selectedMap = {}; this.showStageModal = false;
            this._toast('Stage updated', `Updated ${count} record${count === 1 ? '' : 's'}.`, 'success');
        } catch(e) { this._toast('Error', e.body?.message || 'Update failed.', 'error'); }
        finally    { this.isSaving = false; }
    }

    // ── Bulk: Reassign Owner ──────────────────────────────────────────────────
    get filteredUserOptions() {
        const f   = this._userFilter.toLowerCase();
        const all = this._users.map(u => ({ label: u.Name, value: u.Id }));
        return f ? all.filter(u => u.label.toLowerCase().includes(f)) : all;
    }

    handleBulkOwner() {
        this._userFilter = ''; this._modalOwner = this._users[0]?.Id || '';
        this.showOwnerModal = true;
    }
    handleUserFilterChange(event) {
        this._userFilter = event.target.value;
        const opts = this.filteredUserOptions;
        if (opts.length > 0 && !opts.find(o => o.value === this._modalOwner)) {
            this._modalOwner = opts[0].value;
        }
    }
    handleModalOwnerChange(event) { this._modalOwner = event.target.value; }

    async handleOwnerApply() {
        if (!this._modalOwner) return;
        const ids = [...this.selectedIds]; const count = ids.length;
        this.isSaving = true;
        try {
            await bulkUpdateOwner({ oppIds: ids, ownerId: this._modalOwner });
            await refreshApex(this._wiredOppsResult);
            this._selectedMap = {}; this.showOwnerModal = false;
            this._toast('Owner updated', `Reassigned ${count} record${count === 1 ? '' : 's'}.`, 'success');
        } catch(e) { this._toast('Error', e.body?.message || 'Update failed.', 'error'); }
        finally    { this.isSaving = false; }
    }

    // ── Bulk: Export ──────────────────────────────────────────────────────────
    handleExport() {
        const visCols  = this.visibleColumns;
        const selected = this.rowsWithSelection.filter(r => r.isSelected);
        const headers  = visCols.map(c => c.label);
        const csvRows  = selected.map(r =>
            r.cells.map(cell => `"${String(cell.value ?? '').replace(/"/g, '""')}"`).join(',')
        );
        const csv  = [headers.join(','), ...csvRows].join('\n');
        const link = this.template.querySelector('.ol-export-link');
        link.setAttribute('href', 'data:text/csv;charset=utf-8,' + encodeURIComponent(csv));
        link.setAttribute('download', `opportunities_${new Date().toISOString().slice(0, 10)}.csv`);
        link.click();
    }

    // ── Bulk: Delete ──────────────────────────────────────────────────────────
    get deleteMessage() {
        const n = this.selectionCount;
        return `You are about to permanently delete ${n} opportunit${n === 1 ? 'y' : 'ies'}. This cannot be undone.`;
    }
    get deleteButtonLabel() { return this.isSaving ? 'Deleting…' : 'Delete'; }
    get applyButtonLabel()  { return this.isSaving ? 'Saving…'   : 'Apply';  }

    handleBulkDelete() { this.showDeleteModal = true; }

    async handleDeleteConfirm() {
        const ids = [...this.selectedIds]; const count = ids.length;
        this.isSaving = true;
        try {
            await bulkDeleteOpportunities({ oppIds: ids });
            await refreshApex(this._wiredOppsResult);
            this._selectedMap = {}; this.showDeleteModal = false;
            this._toast('Deleted', `${count} opportunit${count === 1 ? 'y' : 'ies'} deleted.`, 'success');
        } catch(e) { this._toast('Error', e.body?.message || 'Delete failed.', 'error'); }
        finally    { this.isSaving = false; }
    }

    // ── Modal close ───────────────────────────────────────────────────────────
    handleModalClose() {
        this.showStageModal = this.showOwnerModal = this.showDeleteModal = false;
        this.isSaving = false;
    }

    _toast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }
}
