import { LightningElement, api, track } from 'lwc';
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

    connectedCallback() {
        getApplicationFollowUpData({ oppId: this.recordId })
            .then(d => {
                this.data    = d;
                this.toEmail = d.toEmail || '';
                this.subject = d.subject || '';
                this.htmlBody = d.htmlBody || '';
                this.loading = false;
            })
            .catch(err => {
                this.error = (err && err.body && err.body.message) || 'Could not load data.';
                this.loading = false;
            });
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
