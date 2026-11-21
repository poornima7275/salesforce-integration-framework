@IsTest
private class IntegrationLogControllerTest {

    @TestSetup
    static void createLogs() {
        insert new List<Integration_Log__c>{
            new Integration_Log__c(Direction__c = 'Outbound', Method__c = 'POST', Endpoint__c = 'https://api.example.com/v1/invoices',
                Status_Code__c = 503, Success__c = false, Duration_Ms__c = 300, Attempt__c = 1, Correlation_Id__c = 'c-1', Request_Body__c = '{"amount":1}'),
            new Integration_Log__c(Direction__c = 'Outbound', Method__c = 'GET', Endpoint__c = 'https://api.example.com/v1/status',
                Status_Code__c = 200, Success__c = true, Duration_Ms__c = 100, Attempt__c = 1, Correlation_Id__c = 'c-2'),
            new Integration_Log__c(Direction__c = 'Inbound', Method__c = 'POST', Endpoint__c = '/v1/accounts',
                Status_Code__c = 400, Success__c = false, Duration_Ms__c = 200, Attempt__c = 1, Correlation_Id__c = 'c-3')
        };
    }

    private static Integration_Log__c logFor(String correlationId) {
        return [SELECT Id FROM Integration_Log__c WHERE Correlation_Id__c = :correlationId];
    }

    @IsTest
    static void logsCanBeFilteredToFailures() {
        System.runAs(IntegrationTestUtils.createIntegrationUser()) {
            Assert.areEqual(3, IntegrationLogController.getRecentLogs(false, null).size(), 'All logs should be returned');
            Assert.areEqual(2, IntegrationLogController.getRecentLogs(true, 10).size(), 'Only failures should be returned');
        }
    }

    @IsTest
    static void summaryCountsTheLast24Hours() {
        System.runAs(IntegrationTestUtils.createIntegrationUser()) {
            IntegrationLogController.Summary stats = IntegrationLogController.getSummary();
            Assert.areEqual(3, stats.total, 'Three calls were logged');
            Assert.areEqual(2, stats.failures, 'Two calls failed');
            Assert.areEqual(33.3, stats.successRate, 'One in three calls succeeded');
            Assert.areEqual(200, stats.averageDurationMs.intValue(), 'The average duration should be weighted by calls');
        }
    }

    @IsTest
    static void failedOutboundCallCanBeRetried() {
        Test.setMock(HttpCalloutMock.class, new IntegrationTestUtils.MockResponse(200, '{}'));
        Id logId = logFor('c-1').Id;

        Test.startTest();
        Id jobId = IntegrationLogController.retry(logId);
        Test.stopTest();
        Test.getEventBus().deliver();

        Assert.isNotNull(jobId, 'A job id should be returned');
        Integration_Log__c retried = [SELECT Success__c, Correlation_Id__c FROM Integration_Log__c WHERE Success__c = true AND Correlation_Id__c = 'c-1'];
        Assert.isNotNull(retried, 'The retry should reuse the original correlation id');
    }

    @IsTest
    static void inboundAndSuccessfulCallsCannotBeRetried() {
        for (String correlationId : new List<String>{ 'c-2', 'c-3' }) {
            try {
                IntegrationLogController.retry(logFor(correlationId).Id);
                Assert.fail('An exception was expected for ' + correlationId);
            } catch (AuraHandledException e) {
                Assert.isNotNull(e.getMessage(), 'A friendly message should be returned');
            }
        }
    }

    @IsTest
    static void unknownLogIsReported() {
        Integration_Log__c log = logFor('c-1');
        delete log;
        try {
            IntegrationLogController.retry(log.Id);
            Assert.fail('An exception was expected');
        } catch (AuraHandledException e) {
            Assert.areEqual('The log entry was not found.', e.getMessage(), 'The message should explain the problem');
        }
    }
}
