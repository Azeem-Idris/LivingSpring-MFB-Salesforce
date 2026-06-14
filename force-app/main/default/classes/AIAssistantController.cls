public with sharing class AIAssistantController {
    
    private static final String SCHEMA_CONTEXT = 
    'You are a Salesforce SOQL generator for LivingSpring Microfinance Bank. ' +
    'Generate only SELECT SOQL queries. Never generate INSERT, UPDATE, DELETE, MERGE, or UPSERT. ' +
    'Only return the raw SOQL query with no explanation, no markdown, no backticks, no code fences. ' +
    'If you cannot answer with a safe read-only query, return exactly: CLARIFICATION_NEEDED: followed by your question. ' +
    '\n\nIMPORTANT - LOOKUP/RELATIONSHIP FIELDS: ' +
    'LivingSpring_Branch__c is a LOOKUP field on every object (points to LivingSpring_Branch__c object). ' +
    'To filter or display the branch NAME, use the relationship: LivingSpring_Branch__r.Name ' +
    'Never compare LivingSpring_Branch__c directly to a text value like \'Yaba Branch\' - it holds a record ID, not text. ' +
    'Customer__c is a LOOKUP to Account. To filter/display customer name use Customer__r.Name ' +
    'Loan_Product__c is a LOOKUP to Loan_Product__c. To filter/display product name use Loan_Product__r.Name ' +
    'Loan_Application__c (on Loan__c) is a LOOKUP to Loan_Application__c. ' +
    'Recommended_By__c and Officer__c and Assigned_To__c are LOOKUPS to User. Use .Name via relationship if filtering by person name (e.g. Recommended_By__r.Name). ' +
    '\n\nAvailable objects and key fields:' +
    '\n- Account (Customer): Id, Name, KYC_Status__c, BVN_Last4__c, NIN_Last4__c, LivingSpring_Branch__c, LivingSpring_Branch__r.Name, Monthly_Income__c, Employment_Type__c, PersonEmail, PersonBirthdate' +
    '\n- Loan__c: Id, Name, Customer__c, Customer__r.Name, Loan_Application__c, Loan_Product__c, Loan_Product__r.Name, Principal__c, Rate_Snapshot__c, Origination_Fee_Snapshot__c, Insurance_Snapshot__c, Status__c, Disbursement_Date__c, Maturity_Date__c, Days_Past_Due__c, Outstanding_Balance__c, LivingSpring_Branch__c, LivingSpring_Branch__r.Name, Product_Name_Snapshot__c' +
    '\n- Loan_Application__c: Id, Name, Customer__c, Customer__r.Name, Loan_Product__c, Loan_Product__r.Name, Requested_Amount__c, Requested_Tenor__c, Status__c, Affordability_Score__c, Recommended_By__c, Recommended_By__r.Name, LivingSpring_Branch__c, LivingSpring_Branch__r.Name, Submitted_Date__c, Decline_Reason__c' +
    '\n- Repayment_Schedule__c: Id, Name, Loan__c, Loan__r.Name, Installment_Number__c, Due_Date__c, Principal_Due__c, Interest_Due__c, Status__c' +
    '\n- Repayment__c: Id, Name, Loan__c, Loan__r.Name, Repayment_Schedule__c, Amount__c, Payment_Date__c, Channel__c, Reconciled__c, LivingSpring_Branch__c, LivingSpring_Branch__r.Name' +
    '\n- Field_Visit__c: Id, Name, Customer__c, Customer__r.Name, Officer__c, Officer__r.Name, Visit_Date__c, Purpose__c, Visit_Status__c, Loan_Application__c, LivingSpring_Branch__c, LivingSpring_Branch__r.Name' +
    '\n- Collections_Activity__c: Id, Name, Loan__c, Loan__r.Name, Activity_Type__c, Activity_Date__c, Outcome__c, Next_Action_Date__c, Assigned_To__c, Assigned_To__r.Name, LivingSpring_Branch__c' +
    '\n- Cooperative_Group__c: Id, Name, Group_Leader__c, Group_Leader__r.Name, Joint_Liability_Active__c, LivingSpring_Branch__c' +
    '\n- AI_Action_Log__c: Id, Name, User__c, Timestamp__c, Original_Query__c, Generated_DML__c, Target_Records__c, Result_Count__c, Outcome__c' +
    '\n\nQuery rules:' +
    '\n- Always include LIMIT 200 unless the user asks for a count' +
    '\n- For date filters use TODAY, THIS_MONTH, LAST_N_DAYS:30, THIS_WEEK etc' +
    '\n- PAR 30 means Days_Past_Due__c >= 30 on Loan__c' +
    '\n- "In arrears" or "overdue" means Status__c = \'Overdue\' on Loan__c, or Status__c = \'Overdue\' on Repayment_Schedule__c depending on context' +
    '\n- KYC pending means KYC_Status__c = \'Pending Review\' on Account' +
    '\n- When filtering by branch name, ALWAYS use LivingSpring_Branch__r.Name = \'Branch Name\' (capitalize properly, e.g. \'Yaba\' or \'Yaba Branch\' - try without "Branch" suffix first if user says "Yaba branch")' +
    '\n- When user mentions a person\'s name for officer/recommender/assignee, use the relationship .Name field' +
    '\n\nExample queries:' +
    '\nUser: "show all loans in arrears in Yaba branch over 200000"' +
    '\nSOQL: SELECT Id, Name, Customer__r.Name, Principal__c, Days_Past_Due__c, Outstanding_Balance__c FROM Loan__c WHERE Status__c = \'Overdue\' AND LivingSpring_Branch__r.Name LIKE \'%Yaba%\' AND Principal__c > 200000 LIMIT 200' +
    '\nUser: "find every customer onboarded this month with KYC still pending review"' +
    '\nSOQL: SELECT Id, Name, KYC_Status__c, LivingSpring_Branch__r.Name, CreatedDate FROM Account WHERE KYC_Status__c = \'Pending Review\' AND CreatedDate = THIS_MONTH LIMIT 200' +
    '\nUser: "show all loan applications with the branch named yaba branch"' +
    '\nSOQL: SELECT Id, Name, Customer__r.Name, Requested_Amount__c, Status__c, LivingSpring_Branch__r.Name FROM Loan_Application__c WHERE LivingSpring_Branch__r.Name LIKE \'%Yaba%\' LIMIT 200';

    @AuraEnabled
    public static Map<String, Object> sendMessage(String userMessage, String recordId, String objectApiName) {
        
        Map<String, Object> result = new Map<String, Object>();
        String generatedSOQL = '';
        String outcome = 'Error';
        Integer resultCount = 0;
        
        try {
            // Build context-aware prompt
            String contextualMessage = userMessage;
            if (String.isNotBlank(recordId) && String.isNotBlank(objectApiName)) {
                contextualMessage = 'Current record context: ' + objectApiName + ' with Id ' + recordId + '. User question: ' + userMessage;
            }
            
            // Call Gemini
            String geminiResponse = AILLMService.callGemini(SCHEMA_CONTEXT, contextualMessage);
            
            // Check if Gemini needs clarification
            if (geminiResponse.startsWith('CLARIFICATION_NEEDED:')) {
                result.put('type', 'clarification');
                result.put('message', geminiResponse.replace('CLARIFICATION_NEEDED:', '').trim());
                outcome = 'Clarification Requested';
                logInteraction(userMessage, '', objectApiName, 0, outcome);
                return result;
            }
            
            generatedSOQL = geminiResponse.trim();
            
            // Security validation
            validateQuery(generatedSOQL);
            
            // Execute query under running user permissions (with sharing enforced by class declaration)
            List<SObject> records = Database.query(generatedSOQL);
            resultCount = records.size();
            outcome = 'Success';
            
            // Format results
            List<Map<String, Object>> formattedRecords = formatRecords(records);
            
            result.put('type', 'results');
            result.put('records', formattedRecords);
            result.put('count', resultCount);
            result.put('soql', generatedSOQL);
            result.put('message', resultCount + ' record(s) found.');
            
        } catch (AILLMService.AILLMException e) {
            result.put('type', 'error');
            result.put('message', 'The AI service is currently unavailable. Please try again in a moment.');
            outcome = 'Error';
            
        } catch (QueryException e) {
            result.put('type', 'error');
            result.put('message', 'This query could not be answered reliably. Please refine your question or contact your System Administrator.');
            outcome = 'Error';
            
        } catch (SecurityException e) {
            result.put('type', 'error');
            result.put('message', 'This query was blocked for security reasons. Only read operations are permitted.');
            outcome = 'Error';
            
        } catch (Exception e) {
            result.put('type', 'error');
            result.put('message', 'An unexpected error occurred. Please try again.');
            outcome = 'Error';
        }
        
        logInteraction(userMessage, generatedSOQL, objectApiName, resultCount, outcome);
        return result;
    }
    
    private static void validateQuery(String soql) {
        String upperSOQL = soql.toUpperCase();
        
        // Block any write operations absolutely
        List<String> forbiddenKeywords = new List<String>{
            'INSERT', 'UPDATE', 'DELETE', 'MERGE', 'UPSERT', 'UNDELETE'
        };
        
        for (String keyword : forbiddenKeywords) {
            if (upperSOQL.contains(keyword)) {
                throw new SecurityException('Write operations are not permitted in Phase 1.');
            }
        }
        
        // Must start with SELECT
        if (!upperSOQL.trim().startsWith('SELECT')) {
            throw new SecurityException('Only SELECT queries are permitted.');
        }
    }
    
    private static List<Map<String, Object>> formatRecords(List<SObject> records) {
        List<Map<String, Object>> formatted = new List<Map<String, Object>>();
        
        for (SObject record : records) {
            Map<String, Object> row = new Map<String, Object>();
            Map<String, Object> allFields = record.getPopulatedFieldsAsMap();
            
            // Always include Id and Name for linking
            row.put('Id', record.Id);
            row.put('objectType', record.getSObjectType().getDescribe().getName());
            
            for (String fieldName : allFields.keySet()) {
                row.put(fieldName, allFields.get(fieldName));
            }
            
            formatted.add(row);
        }
        
        return formatted;
    }
    
    private static void logInteraction(String originalQuery, String generatedSOQL, String targetObject, Integer resultCount, String outcome) {
    try {
        AI_Action_Log__c log = new AI_Action_Log__c();
        log.User__c = UserInfo.getUserId();
        log.Timestamp__c = DateTime.now();
        log.Original_Query__c = originalQuery;
        log.Generated_DML__c = generatedSOQL;
        log.Target_Records__c = targetObject;
        log.Result_Count__c = resultCount;
        log.Outcome__c = outcome;
        
        AILogWriter.writeLog(log);
    } catch (Exception e) {
        System.debug('Logging failed: ' + e.getMessage());
    }
}
    
    public class SecurityException extends Exception {}
}