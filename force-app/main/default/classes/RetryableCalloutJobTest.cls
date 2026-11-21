@IsTest
private class RetryableCalloutJobTest {

    private static HttpCalloutService.CalloutRequest invoiceRequest() {
        return new HttpCalloutService.CalloutRequest('POST', 'https://api.example.com/v1/invoices', '{"amount":100}');
    }

    @IsTest
    static void successIsNotRetried() {
        Test.setMock(HttpCalloutMock.class, new IntegrationTestUtils.MockResponse(201, '{"id":"INV-1"}'));

        Test.startTest();
        System.enqueueJob(new RetryableCalloutJob(invoiceRequest()));
        Test.stopTest();
        Test.getEventBus().deliver();

        Assert.areEqual(1, [SELECT COUNT() FROM Integration_Log__c WHERE Success__c = true], 'One successful call should be logged');
    }

    @IsTest
    static void temporaryFailureSchedulesARetry() {
        Test.setMock(HttpCalloutMock.class, new IntegrationTestUtils.MockResponse(503, 'Service Unavailable'));
        HttpCalloutService.CalloutRequest request = invoiceRequest();
        RetryableCalloutJob.retriesEnabled = false;

        new RetryableCalloutJob(request).execute(null);

        Assert.areEqual(1, RetryableCalloutJob.lastRetryDelayMinutes, 'The first retry should wait 1 minute');
        Assert.areEqual(2, request.attempt, 'The retry should be attempt 2');
    }

    @IsTest
    static void permanentFailureIsNotRetried() {
        Test.setMock(HttpCalloutMock.class, new IntegrationTestUtils.MockResponse(404, 'Not Found'));

        new RetryableCalloutJob(invoiceRequest()).execute(null);

        Assert.isNull(RetryableCalloutJob.lastRetryDelayMinutes, 'A 404 must not be retried');
    }

    @IsTest
    static void retriesStopAfterMaxAttempts() {
        Test.setMock(HttpCalloutMock.class, new IntegrationTestUtils.MockResponse(503, 'Service Unavailable'));
        HttpCalloutService.CalloutRequest request = invoiceRequest();
        request.attempt = RetryableCalloutJob.MAX_ATTEMPTS;

        new RetryableCalloutJob(request).execute(null);

        Assert.isNull(RetryableCalloutJob.lastRetryDelayMinutes, 'No retry after the last attempt');
    }

    @IsTest
    static void backoffGrowsExponentiallyAndIsCapped() {
        Assert.areEqual(1, RetryableCalloutJob.backoffMinutes(1), 'First retry after 1 minute');
        Assert.areEqual(2, RetryableCalloutJob.backoffMinutes(2), 'Then 2 minutes');
        Assert.areEqual(4, RetryableCalloutJob.backoffMinutes(3), 'Then 4 minutes');
        Assert.areEqual(10, RetryableCalloutJob.backoffMinutes(8), 'Never more than 10 minutes');
    }
}
