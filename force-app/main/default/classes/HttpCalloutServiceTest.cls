@IsTest
private class HttpCalloutServiceTest {

    @IsTest
    static void successfulCalloutIsLoggedWithCorrelationId() {
        IntegrationTestUtils.MockResponse mock = new IntegrationTestUtils.MockResponse(200, '{"id":"INV-1"}');
        Test.setMock(HttpCalloutMock.class, mock);

        Test.startTest();
        HttpCalloutService.CalloutResult result = HttpCalloutService.send(
            new HttpCalloutService.CalloutRequest('post', 'https://api.example.com/v1/invoices', '{"amount":100}')
        );
        IntegrationLogger.flush();
        Test.stopTest();

        Assert.isTrue(result.success, 'A 200 response is a success');
        Assert.isFalse(result.retryable, 'A success is never retried');
        Assert.areEqual('{"id":"INV-1"}', result.body, 'The response body should be returned');
        Assert.areEqual('POST', mock.lastRequest.getMethod(), 'The method should be upper-cased');
        Assert.isNotNull(mock.lastRequest.getHeader('X-Correlation-Id'), 'A correlation id header should be sent');

        Integration_Log__c log = [SELECT Direction__c, Method__c, Status_Code__c, Success__c, Attempt__c, Correlation_Id__c, Request_Body__c FROM Integration_Log__c];
        Assert.areEqual('Outbound', log.Direction__c, 'The log should be an outbound call');
        Assert.areEqual(200, log.Status_Code__c.intValue(), 'The status code should be logged');
        Assert.isTrue(log.Success__c, 'The log should be marked as success');
        Assert.areEqual(mock.lastRequest.getHeader('X-Correlation-Id'), log.Correlation_Id__c, 'The logged correlation id should match the header');
        Assert.areEqual('{"amount":100}', log.Request_Body__c, 'The request body should be logged');
    }

    @IsTest
    static void serverErrorIsRetryable() {
        Test.setMock(HttpCalloutMock.class, new IntegrationTestUtils.MockResponse(503, 'Service Unavailable'));

        HttpCalloutService.CalloutResult result = HttpCalloutService.send(
            new HttpCalloutService.CalloutRequest('GET', 'https://api.example.com/v1/status', null)
        );

        Assert.isFalse(result.success, 'A 503 is a failure');
        Assert.isTrue(result.retryable, 'A 503 should be retried');
        Assert.isTrue(result.errorMessage.contains('503'), 'The error should include the status code');
        Assert.areEqual(1, IntegrationLogger.pendingCount(), 'The failure should be logged');
    }

    @IsTest
    static void clientErrorIsNotRetryable() {
        Test.setMock(HttpCalloutMock.class, new IntegrationTestUtils.MockResponse(400, '{"error":"bad request"}'));

        HttpCalloutService.CalloutResult result = HttpCalloutService.send(
            new HttpCalloutService.CalloutRequest('POST', 'https://api.example.com/v1/invoices', '{}')
        );

        Assert.isFalse(result.success, 'A 400 is a failure');
        Assert.isFalse(result.retryable, 'A 400 will fail again, so it must not be retried');
    }

    @IsTest
    static void timeoutIsRetryable() {
        Test.setMock(HttpCalloutMock.class, new IntegrationTestUtils.MockResponse(true));

        HttpCalloutService.CalloutResult result = HttpCalloutService.send(
            new HttpCalloutService.CalloutRequest('GET', 'https://api.example.com/v1/slow', null)
        );

        Assert.isFalse(result.success, 'A timeout is a failure');
        Assert.isTrue(result.retryable, 'A timeout should be retried');
        Assert.isNull(result.statusCode, 'There is no status code when the call times out');
        Assert.areEqual('Read timed out', result.errorMessage, 'The exception message should be returned');
    }

    @IsTest
    static void missingEndpointIsRejected() {
        try {
            HttpCalloutService.send(new HttpCalloutService.CalloutRequest('GET', '', null));
            Assert.fail('An exception was expected');
        } catch (IllegalArgumentException e) {
            Assert.isTrue(e.getMessage().contains('endpoint'), 'The message should explain what is missing');
        }
    }

    @IsTest
    static void longBodiesAreTruncatedInTheLog() {
        String bigBody = 'x'.repeat(IntegrationLogger.MAX_BODY_LENGTH + 500);
        Test.setMock(HttpCalloutMock.class, new IntegrationTestUtils.MockResponse(200, bigBody));

        Test.startTest();
        HttpCalloutService.send(new HttpCalloutService.CalloutRequest('GET', 'https://api.example.com/v1/export', null));
        IntegrationLogger.flush();
        Test.stopTest();

        Integration_Log__c log = [SELECT Response_Body__c FROM Integration_Log__c];
        Assert.areEqual(IntegrationLogger.MAX_BODY_LENGTH, log.Response_Body__c.length(), 'The body should be truncated');
    }
}
