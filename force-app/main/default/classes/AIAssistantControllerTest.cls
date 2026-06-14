@isTest
public class AIAssistantControllerTest {
    
    private class MockSOQLResponse implements HttpCalloutMock {
        String returnText;
        MockSOQLResponse(String returnText) {
            this.returnText = returnText;
        }
        public HTTPResponse respond(HTTPRequest req) {
            HttpResponse res = new HttpResponse();
            res.setHeader('Content-Type', 'application/json');
            res.setStatusCode(200);
            // Escape quotes for JSON safety
            String escaped = returnText.replace('"', '\\"');
            res.setBody('{"candidates":[{"content":{"parts":[{"text":"' + escaped + '"}]}}]}');
            return res;
        }
    }
    
    private class MockHttpError implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(500);
            res.setBody('{"error":"server error"}');
            return res;
        }
    }
    
    @testSetup
    static void setupData() {
        Account testAccount = new Account(
            Name = 'Test Customer Mary',
            KYC_Status__c = 'Active',
            BVN__c = '12345678901',
            NIN__c = '98765432109',
            Birth_Date__c = Date.newInstance(1990, 1, 1)
    );
    insert testAccount;
}
    
    @isTest
    static void testSendMessage_SuccessfulQuery() {
        Test.setMock(HttpCalloutMock.class, new MockSOQLResponse('SELECT Id, Name FROM Account LIMIT 200'));
        
        Test.startTest();
        Map<String, Object> result = AIAssistantController.sendMessage('show all customers', '', 'Account');
        Test.stopTest();
        
        System.assertEquals('results', result.get('type'), 'Should return results type');
        System.assertEquals(1, result.get('count'), 'Should find the test account');
    }
    
    @isTest
    static void testSendMessage_NoRecordsFound() {
        Test.setMock(HttpCalloutMock.class, new MockSOQLResponse('SELECT Id, Name FROM Account WHERE Name = \'NoSuchCustomer999\' LIMIT 200'));
        
        Test.startTest();
        Map<String, Object> result = AIAssistantController.sendMessage('find customer xyz', '', 'Account');
        Test.stopTest();
        
        System.assertEquals('results', result.get('type'));
        System.assertEquals(0, result.get('count'));
    }
    
    @isTest
    static void testSendMessage_ClarificationNeeded() {
        Test.setMock(HttpCalloutMock.class, new MockSOQLResponse('CLARIFICATION_NEEDED: Which branch do you mean?'));
        
        Test.startTest();
        Map<String, Object> result = AIAssistantController.sendMessage('show loans', '', '');
        Test.stopTest();
        
        System.assertEquals('clarification', result.get('type'));
        System.assertEquals('Which branch do you mean?', result.get('message'));
    }
    
    @isTest
    static void testSendMessage_BlocksDeleteStatement() {
        Test.setMock(HttpCalloutMock.class, new MockSOQLResponse('DELETE FROM Account WHERE Id = \'001xx\''));
        
        Test.startTest();
        Map<String, Object> result = AIAssistantController.sendMessage('delete a customer', '', 'Account');
        Test.stopTest();
        
        System.assertEquals('error', result.get('type'));
        System.assertEquals('This query was blocked for security reasons. Only read operations are permitted.', result.get('message'));
    }
    
    @isTest
    static void testSendMessage_BlocksUpdateStatement() {
        Test.setMock(HttpCalloutMock.class, new MockSOQLResponse('UPDATE Account SET Name = \'Hacked\''));
        
        Test.startTest();
        Map<String, Object> result = AIAssistantController.sendMessage('change customer name', '', 'Account');
        Test.stopTest();
        
        System.assertEquals('error', result.get('type'));
    }
    
    @isTest
    static void testSendMessage_InvalidSOQL() {
        Test.setMock(HttpCalloutMock.class, new MockSOQLResponse('SELECT Id FROM NonExistentObject__c LIMIT 200'));
        
        Test.startTest();
        Map<String, Object> result = AIAssistantController.sendMessage('show invalid object', '', '');
        Test.stopTest();
        
        System.assertEquals('error', result.get('type'));
        System.assertEquals('This query could not be answered reliably. Please refine your question or contact your System Administrator.', result.get('message'));
    }
    
    @isTest
    static void testSendMessage_LLMUnavailable() {
        Test.setMock(HttpCalloutMock.class, new MockHttpError());
        
        Test.startTest();
        Map<String, Object> result = AIAssistantController.sendMessage('show loans', '', '');
        Test.stopTest();
        
        System.assertEquals('error', result.get('type'));
        System.assertEquals('The AI service is currently unavailable. Please try again in a moment.', result.get('message'));
    }
    
    @isTest
    static void testSendMessage_WithRecordContext() {
        Test.setMock(HttpCalloutMock.class, new MockSOQLResponse('SELECT Id, Name FROM Account LIMIT 200'));
        Account acc = [SELECT Id FROM Account LIMIT 1];
        
        Test.startTest();
        Map<String, Object> result = AIAssistantController.sendMessage('tell me about this customer', acc.Id, 'Account');
        Test.stopTest();
        
        System.assertEquals('results', result.get('type'));
    }
    
    @isTest
    static void testLoggingOccurs() {
        Test.setMock(HttpCalloutMock.class, new MockSOQLResponse('SELECT Id, Name FROM Account LIMIT 200'));
        
        Test.startTest();
        AIAssistantController.sendMessage('show customers', '', 'Account');
        Test.stopTest();
        
        List<AI_Action_Log__c> logs = [SELECT Id, Outcome__c, Original_Query__c FROM AI_Action_Log__c];
        System.assertEquals(1, logs.size(), 'One log entry should be created');
        System.assertEquals('Success', logs[0].Outcome__c);
        System.assertEquals('show customers', logs[0].Original_Query__c);
    }
}