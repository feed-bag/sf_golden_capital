import { LightningElement, api, wire, track } from 'lwc';
import { CloseActionScreenEvent } from 'lightning/actions';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getApplicationFollowUpData from '@salesforce/apex/EmailFollowUpController.getApplicationFollowUpData';
import sendApplicationFollowUp    from '@salesforce/apex/EmailFollowUpController.sendApplicationFollowUp';

export default class ApplicationFollowUp extends LightningElement {
    @api recordId;
    @track loading = true;
    @track sending = false;
    @track error;
    @track data;
    @track toEmail = '';
    @track subject = '';
    @track htmlBody = '';

    // Wire fires only when recordId is populated by the Quick Action framework,
    // so we avoid the race where connectedCallback runs before @api recordId is set.
    @wire(getApplicationFollowUpData, { oppId: '$recordId' })
    wired({ data, error }) {
        if (!this.recordId) return;
        if (data) {
            this.data    = data;
            this.toEmail = data.toEmail || '';
            this.subject = data.subject || '';
            this.htmlBody = data.htmlBody || '';
            this.error   = undefined;
            this.loading = false;
        } else if (error) {
            this.error = (error && error.body && error.body.message) || 'Could not load data.';
            this.loading = false;
        }
    }

    handleToChange(e)      { this.toEmail  = e.target.value; }
    handleSubjectChange(e) { this.subject  = e.target.value; }
    handleBodyChange(e)    { this.htmlBody = e.target.value; }

    handleCancel() {
        this.dispatchEvent(new CloseActionScreenEvent());
    }

    handleSend() {
        if (!this.toEmail) {
            this.error = 'Recipient email is required.';
            return;
        }
        this.sending = true;
        this.error = undefined;
        sendApplicationFollowUp({
            oppId:    this.recordId,
            toEmail:  this.toEmail,
            subject:  this.subject,
            htmlBody: this.htmlBody
        })
            .then(() => {
                this.dispatchEvent(new ShowToastEvent({
                    title: 'Email sent',
                    message: `Sent to ${this.toEmail}`,
                    variant: 'success'
                }));
                this.dispatchEvent(new CloseActionScreenEvent());
            })
            .catch(err => {
                this.sending = false;
                this.error = (err && err.body && err.body.message) || 'Send failed.';
            });
    }
}
