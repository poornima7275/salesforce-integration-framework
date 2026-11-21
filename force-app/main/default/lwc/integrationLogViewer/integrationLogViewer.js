import { LightningElement, wire } from 'lwc';
import { refreshApex } from '@salesforce/apex';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getRecentLogs from '@salesforce/apex/IntegrationLogController.getRecentLogs';
import getSummary from '@salesforce/apex/IntegrationLogController.getSummary';
import retry from '@salesforce/apex/IntegrationLogController.retry';

const COLUMNS = [
    { label: 'Log', fieldName: 'recordUrl', type: 'url', typeAttributes: { label: { fieldName: 'Name' } }, initialWidth: 120 },
    { label: 'Time', fieldName: 'CreatedDate', type: 'date', typeAttributes: { month: 'short', day: '2-digit', hour: '2-digit', minute: '2-digit', second: '2-digit' } },
    { label: 'Direction', fieldName: 'Direction__c', initialWidth: 100 },
    { label: 'Method', fieldName: 'Method__c', initialWidth: 90 },
    { label: 'Endpoint', fieldName: 'Endpoint__c', wrapText: true },
    { label: 'Status', fieldName: 'Status_Code__c', type: 'number', initialWidth: 90, cellAttributes: { class: { fieldName: 'statusClass' } } },
    { label: 'ms', fieldName: 'Duration_Ms__c', type: 'number', initialWidth: 80 },
    { label: 'Attempt', fieldName: 'Attempt__c', type: 'number', initialWidth: 90 },
    { label: 'Error', fieldName: 'Error_Message__c', wrapText: true },
    { type: 'action', typeAttributes: { rowActions: (row, done) => done(row.actions) } }
];

export default class IntegrationLogViewer extends LightningElement {
    columns = COLUMNS;
    failuresOnly = false;
    rows = [];
    summary;
    error;

    wiredLogs;
    wiredSummary;

    @wire(getRecentLogs, { failuresOnly: '$failuresOnly', limitSize: 100 })
    handleLogs(result) {
        this.wiredLogs = result;
        if (result.data) {
            this.error = undefined;
            this.rows = result.data.map((log) => ({
                ...log,
                recordUrl: `/${log.Id}`,
                statusClass: log.Success__c ? 'slds-text-color_success' : 'slds-text-color_error',
                actions: [
                    {
                        label: 'Retry',
                        name: 'retry',
                        disabled: log.Success__c || log.Direction__c !== 'Outbound'
                    }
                ]
            }));
        } else if (result.error) {
            this.error = this.reduceError(result.error);
            this.rows = [];
        }
    }

    @wire(getSummary)
    handleSummary(result) {
        this.wiredSummary = result;
        if (result.data) {
            this.summary = result.data;
        }
    }

    get hasRows() {
        return this.rows.length > 0;
    }

    handleFailuresToggle(event) {
        this.failuresOnly = event.target.checked;
    }

    async handleRefresh() {
        await Promise.all([refreshApex(this.wiredLogs), refreshApex(this.wiredSummary)]);
    }

    async handleRowAction(event) {
        const { action, row } = event.detail;
        if (action.name !== 'retry') {
            return;
        }
        try {
            await retry({ logId: row.Id });
            this.toast('Retry queued', `${row.Method__c} ${row.Endpoint__c} will be sent again in the background.`, 'success');
        } catch (e) {
            this.toast('Retry failed', this.reduceError(e), 'error');
        }
    }

    toast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }

    reduceError(error) {
        if (Array.isArray(error?.body)) {
            return error.body.map((e) => e.message).join(', ');
        }
        return error?.body?.message || error?.message || 'Unknown error';
    }
}
