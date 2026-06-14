public class AILLMService {
    
    private static final String NAMED_CREDENTIAL = 'callout:GeminiAI';
    private static final String GEMINI_MODEL_PATH = '/v1beta/models/gemini-2.5-flash:generateContent';
    
    public static String callGemini(String systemPrompt, String userMessage) {
        
        String apiKey = getApiKey();
        String endpoint = NAMED_CREDENTIAL + GEMINI_MODEL_PATH + '?key=' + apiKey;
        
        HttpRequest req = new HttpRequest();
        req.setEndpoint(endpoint);
        req.setMethod('POST');
        req.setHeader('Content-Type', 'application/json');
        req.setTimeout(30000);
        
        Map<String, Object> requestBody = new Map<String, Object>();
        
        Map<String, Object> systemInstruction = new Map<String, Object>();
        List<Map<String, Object>> systemParts = new List<Map<String, Object>>();
        Map<String, Object> systemPart = new Map<String, Object>();
        systemPart.put('text', systemPrompt);
        systemParts.add(systemPart);
        systemInstruction.put('parts', systemParts);
        requestBody.put('systemInstruction', systemInstruction);
        
        List<Map<String, Object>> contents = new List<Map<String, Object>>();
        Map<String, Object> content = new Map<String, Object>();
        List<Map<String, Object>> parts = new List<Map<String, Object>>();
        Map<String, Object> part = new Map<String, Object>();
        part.put('text', userMessage);
        parts.add(part);
        content.put('parts', parts);
        content.put('role', 'user');
        contents.add(content);
        requestBody.put('contents', contents);
        
        Map<String, Object> generationConfig = new Map<String, Object>();
        generationConfig.put('maxOutputTokens', 1024);
        generationConfig.put('temperature', 0.2);
        requestBody.put('generationConfig', generationConfig);
        
        req.setBody(JSON.serialize(requestBody));
        
        Http http = new Http();
        HttpResponse res;
        
        try {
            res = http.send(req);
        } catch (Exception e) {
            throw new AILLMException('LLM service is currently unavailable. Please try again later. Error: ' + e.getMessage());
        }
        
        if (res.getStatusCode() != 200) {
            throw new AILLMException('LLM service returned an error (' + res.getStatusCode() + '). Please try again later. Details: ' + res.getBody());
        }
        
        Map<String, Object> responseMap = (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
        List<Object> candidates = (List<Object>) responseMap.get('candidates');
        Map<String, Object> firstCandidate = (Map<String, Object>) candidates[0];
        Map<String, Object> contentResponse = (Map<String, Object>) firstCandidate.get('content');
        List<Object> responseParts = (List<Object>) contentResponse.get('parts');
        Map<String, Object> firstPart = (Map<String, Object>) responseParts[0];
        return (String) firstPart.get('text');
    }
    
    private static String getApiKey() {
        API_Key__mdt setting = [
            SELECT Key_Value__c 
            FROM API_Key__mdt 
            WHERE DeveloperName = 'Gemini_API_Key' 
            LIMIT 1
        ];
        return setting.Key_Value__c;
    }
    
    public class AILLMException extends Exception {}
}