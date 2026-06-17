@isTest
public class AILLMServiceTest {
    
    private class GeminiMockSuccess implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            HttpResponse res = new HttpResponse();
            res.setHeader('Content-Type', 'application/json');
            res.setStatusCode(200);
            res.setBody('{"candidates":[{"content":{"parts":[{"text":"SELECT Id, Name FROM Account LIMIT 200"}]}}]}');
            return res;
        }
    }
    
    private class GeminiMockFailure implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            HttpResponse res = new HttpResponse();
            res.setHeader('Content-Type', 'application/json');
            res.setStatusCode(500);
            res.setBody('{"error":{"message":"Internal server error"}}');
            return res;
        }
    }
    
    @isTest
    static void testCallGemini_Success() {
        Test.setMock(HttpCalloutMock.class, new GeminiMockSuccess());
        
        Test.startTest();
        String result = AILLMService.callGemini('System prompt', 'User question');
        Test.stopTest();
        
        System.assertEquals('SELECT Id, Name FROM Account LIMIT 200', result, 'Should return the generated SOQL text');
    }
    
    @isTest
    static void testCallGemini_HttpError() {
        Test.setMock(HttpCalloutMock.class, new GeminiMockFailure());
        
        Test.startTest();
        try {
            AILLMService.callGemini('System prompt', 'User question');
            System.assert(false, 'Should have thrown AILLMException');
        } catch (AILLMService.AILLMException e) {
            System.assert(e.getMessage().contains('500'), 'Exception should mention status code');
        }
        Test.stopTest();
    }
}