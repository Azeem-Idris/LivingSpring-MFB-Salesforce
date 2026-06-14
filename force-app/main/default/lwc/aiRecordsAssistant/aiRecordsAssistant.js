import { LightningElement, api, track } from 'lwc';
import sendMessage from '@salesforce/apex/AIAssistantController.sendMessage';

export default class AiRecordsAssistant extends LightningElement {
    @api recordId;
    @api objectApiName;
    
    @track messages = [];
    @track currentMessage = '';
    @track isLoading = false;
    
    messageIdCounter = 0;
    
    connectedCallback() {
        this.addMessage(
            'assistant',
            'Hello! I am the LivingSpring AI Assistant. Ask me anything about customers, loans, repayments, or compliance data.'
        );
    }
    
    handleMessageChange(event) {
        this.currentMessage = event.target.value;
    }
    
    handleKeyDown(event) {
        if (event.key === 'Enter' && !event.shiftKey) {
            event.preventDefault();
            this.sendMessage();
        }
    }
    
    async sendMessage() {
        const message = this.currentMessage.trim();
        if (!message || this.isLoading) return;
        
        this.addMessage('user', message);
        this.currentMessage = '';
        this.isLoading = true;
        
        try {
            const result = await sendMessage({
                userMessage: message,
                recordId: this.recordId || '',
                objectApiName: this.objectApiName || ''
            });
            
            if (result.type === 'results') {
                if (result.count === 0) {
                    this.addMessage('assistant', 'No records match your query. Try refining your search.');
                } else {
                    this.addMessageWithRecords(
                        result.count + ' record(s) found:',
                        result.records
                    );
                }
            } else if (result.type === 'clarification') {
                this.addMessage('assistant', result.message);
            } else if (result.type === 'error') {
                this.addMessage('error', result.message);
            }
            
        } catch (error) {
            this.addMessage(
                'error',
                'The AI service is currently unavailable. Please try again later.'
            );
        } finally {
            this.isLoading = false;
            this.scrollToBottom();
        }
    }
    
    addMessage(type, text) {
        const cssMap = {
            user: 'message user-message',
            assistant: 'message assistant-message',
            error: 'message error-message'
        };
        
        this.messages = [...this.messages, {
            id: this.messageIdCounter++,
            text: text,
            cssClass: cssMap[type] || 'message assistant-message',
            time: new Date().toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' }),
            hasRecords: false,
            columns: [],
            rows: []
        }];
    }
    
    addMessageWithRecords(text, records) {
        if (!records || records.length === 0) return;
        
        const excludeFields = ['objectType'];
        const allKeys = Object.keys(records[0]).filter(k => !excludeFields.includes(k));
        const priorityFields = ['Name', 'Status__c', 'Principal__c', 'Outstanding_Balance__c', 
                                'Days_Past_Due__c', 'Requested_Amount__c', 'KYC_Status__c',
                                'Disbursement_Date__c', 'Due_Date__c', 'Amount__c'];
        let columns = allKeys.filter(k => priorityFields.includes(k));
        if (columns.length === 0) columns = allKeys.slice(0, 5);
        if (!columns.includes('Name') && allKeys.includes('Name')) columns.unshift('Name');
        
        const rows = records.map(record => ({
            Id: record.Id,
            cells: columns.map(col => ({
                key: col,
                value: record[col] !== null && record[col] !== undefined ? String(record[col]) : '-',
                isLink: col === 'Name' && record.Id,
                url: col === 'Name' ? '/' + record.Id : null
            }))
        }));
        
        this.messages = [...this.messages, {
            id: this.messageIdCounter++,
            text: text,
            cssClass: 'message assistant-message',
            time: new Date().toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' }),
            hasRecords: true,
            columns: columns,
            rows: rows
        }];
    }
    
    scrollToBottom() {
        setTimeout(() => {
            const chatBody = this.template.querySelector('.chat-body');
            if (chatBody) chatBody.scrollTop = chatBody.scrollHeight;
        }, 100);
    }
    
    resetChat() {
        this.messages = [];
        this.messageIdCounter = 0;
        this.addMessage(
            'assistant',
            'Hello! I am the LivingSpring AI Assistant. Ask me anything about customers, loans, repayments, or compliance data.'
        );
    }
}