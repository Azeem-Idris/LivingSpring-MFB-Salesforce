@isTest
public class AILogWriterTest {
    
    @isTest
    static void testWriteLog_Success() {
        AI_Action_Log__c log = new AI_Action_Log__c();
        log.User__c = UserInfo.getUserId();
        log.Timestamp__c = DateTime.now();
        log.Original_Query__c = 'Test query';
        log.Generated_DML__c = 'SELECT Id FROM Account';
        log.Target_Records__c = 'Account';
        log.Result_Count__c = 5;
        log.Outcome__c = 'Success';
        
        Test.startTest();
        AILogWriter.writeLog(log);
        Test.stopTest();
        
        List<AI_Action_Log__c> logs = [SELECT Id, Original_Query__c, Outcome__c FROM AI_Action_Log__c WHERE Id = :log.Id];
        System.assertEquals(1, logs.size(), 'Log record should be inserted');
        System.assertEquals('Success', logs[0].Outcome__c);
    }
}