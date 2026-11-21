/**
 * Collects log entries during a transaction and publishes them as
 * Integration_Log_Event__e platform events.
 *
 * Events are published immediately, so the log is kept even when the
 * calling transaction later fails and rolls back. Entries are buffered
 * (instead of published one by one) so that several callouts can run in one
 * transaction before the publish happens.
 */
public without sharing class IntegrationLogger {

    @TestVisible
    private static final Integer MAX_BODY_LENGTH = 32000;

    @TestVisible
    private static List<Integration_Log_Event__e> buffer = new List<Integration_Log_Event__e>();

    public static void logOutbound(HttpCalloutService.CalloutRequest request, HttpCalloutService.CalloutResult result) {
        buffer.add(new Integration_Log_Event__e(
            Direction__c = 'Outbound',
            Endpoint__c = request.endpoint.left(255),
            Method__c = request.method.toUpperCase(),
            Status_Code__c = result.statusCode,
            Success__c = result.success,
            Duration_Ms__c = result.durationMs,
            Attempt__c = request.attempt,
            Correlation_Id__c = request.correlationId,
            Request_Body__c = truncate(request.body),
            Response_Body__c = truncate(result.body),
            Error_Message__c = result.errorMessage == null ? null : result.errorMessage.left(255)
        ));
    }

    public static void logInbound(String endpoint, String method, Integer statusCode, String requestBody, String responseBody, String correlationId) {
        Boolean success = statusCode >= 200 && statusCode < 300;
        buffer.add(new Integration_Log_Event__e(
            Direction__c = 'Inbound',
            Endpoint__c = endpoint == null ? null : endpoint.left(255),
            Method__c = method,
            Status_Code__c = statusCode,
            Success__c = success,
            Attempt__c = 1,
            Correlation_Id__c = correlationId,
            Request_Body__c = truncate(requestBody),
            Response_Body__c = truncate(responseBody),
            Error_Message__c = success ? null : 'HTTP ' + statusCode
        ));
    }

    public static Integer pendingCount() {
        return buffer.size();
    }

    public static void flush() {
        if (buffer.isEmpty()) {
            return;
        }
        List<Database.SaveResult> results = EventBus.publish(buffer);
        buffer = new List<Integration_Log_Event__e>();
        for (Database.SaveResult result : results) {
            if (!result.isSuccess()) {
                System.debug(LoggingLevel.ERROR, 'Integration log could not be published: ' + result.getErrors());
            }
        }
    }

    /** Called by IntegrationLogEventTrigger: turns events into Integration_Log__c rows. */
    public static void saveLogs(List<Integration_Log_Event__e> events) {
        List<Integration_Log__c> logs = new List<Integration_Log__c>();
        for (Integration_Log_Event__e e : events) {
            logs.add(new Integration_Log__c(
                Direction__c = e.Direction__c,
                Endpoint__c = e.Endpoint__c,
                Method__c = e.Method__c,
                Status_Code__c = e.Status_Code__c,
                Success__c = e.Success__c,
                Duration_Ms__c = e.Duration_Ms__c,
                Attempt__c = e.Attempt__c,
                Correlation_Id__c = e.Correlation_Id__c,
                Request_Body__c = e.Request_Body__c,
                Response_Body__c = e.Response_Body__c,
                Error_Message__c = e.Error_Message__c
            ));
        }
        insert logs;
    }

    private static String truncate(String value) {
        return value == null ? null : value.left(MAX_BODY_LENGTH);
    }
}
