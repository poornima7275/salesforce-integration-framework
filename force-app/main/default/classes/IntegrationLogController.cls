/**
 * Apex controller for the integrationLogViewer Lightning Web Component.
 */
public with sharing class IntegrationLogController {

    private static final Integer DEFAULT_LIMIT = 50;
    private static final Integer MAX_LIMIT = 500;

    public class Summary {
        @AuraEnabled public Integer total = 0;
        @AuraEnabled public Integer failures = 0;
        @AuraEnabled public Decimal successRate = 100;
        @AuraEnabled public Decimal averageDurationMs = 0;
    }

    @AuraEnabled(cacheable=true)
    public static List<Integration_Log__c> getRecentLogs(Boolean failuresOnly, Integer limitSize) {
        Integer rows = (limitSize == null || limitSize <= 0) ? DEFAULT_LIMIT : Math.min(limitSize, MAX_LIMIT);
        String soql =
            'SELECT Id, Name, CreatedDate, Direction__c, Method__c, Endpoint__c, Status_Code__c, Success__c, ' +
            'Duration_Ms__c, Attempt__c, Correlation_Id__c, Error_Message__c ' +
            'FROM Integration_Log__c ' +
            (failuresOnly == true ? 'WHERE Success__c = false ' : '') +
            'ORDER BY CreatedDate DESC LIMIT :rows';
        return Database.queryWithBinds(soql, new Map<String, Object>{ 'rows' => rows }, AccessLevel.USER_MODE);
    }

    @AuraEnabled(cacheable=true)
    public static Summary getSummary() {
        Summary stats = new Summary();
        Datetime since = Datetime.now().addHours(-24);
        for (AggregateResult row : [
            SELECT Success__c success, COUNT(Id) calls, AVG(Duration_Ms__c) avgDuration
            FROM Integration_Log__c
            WHERE CreatedDate >= :since
            WITH USER_MODE
            GROUP BY Success__c
        ]) {
            Integer calls = (Integer) row.get('calls');
            stats.total += calls;
            if ((Boolean) row.get('success') == false) {
                stats.failures += calls;
            }
            Decimal avg = (Decimal) row.get('avgDuration');
            if (avg != null) {
                stats.averageDurationMs += avg * calls;
            }
        }
        if (stats.total > 0) {
            stats.averageDurationMs = (stats.averageDurationMs / stats.total).setScale(0);
            stats.successRate = (100 * (Decimal) (stats.total - stats.failures) / stats.total).setScale(1);
        }
        return stats;
    }

    /** Re-sends a failed outbound call in the background. Returns the Queueable job id. */
    @AuraEnabled
    public static Id retry(Id logId) {
        List<Integration_Log__c> logs = [
            SELECT Id, Direction__c, Method__c, Endpoint__c, Request_Body__c, Correlation_Id__c, Success__c
            FROM Integration_Log__c
            WHERE Id = :logId
            WITH USER_MODE
        ];
        if (logs.isEmpty()) {
            throw newAuraException('The log entry was not found.');
        }
        Integration_Log__c log = logs[0];
        if (log.Direction__c != 'Outbound') {
            throw newAuraException('Only outbound calls can be retried from Salesforce.');
        }
        if (log.Success__c) {
            throw newAuraException('This call already succeeded.');
        }

        HttpCalloutService.CalloutRequest request = new HttpCalloutService.CalloutRequest(log.Method__c, log.Endpoint__c, log.Request_Body__c);
        request.correlationId = log.Correlation_Id__c;
        return System.enqueueJob(new RetryableCalloutJob(request));
    }

    private static AuraHandledException newAuraException(String message) {
        AuraHandledException e = new AuraHandledException(message);
        e.setMessage(message);
        return e;
    }
}
