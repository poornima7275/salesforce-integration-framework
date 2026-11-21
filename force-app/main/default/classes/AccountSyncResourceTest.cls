@IsTest
private class AccountSyncResourceTest {

    private static void setRequest(String method, String uri, String body) {
        RestRequest request = new RestRequest();
        request.httpMethod = method;
        request.requestURI = uri;
        request.addHeader('X-Correlation-Id', 'test-correlation-id');
        if (body != null) {
            request.requestBody = Blob.valueOf(body);
        }
        RestContext.request = request;
        RestContext.response = new RestResponse();
    }

    private static List<Object> responseRows() {
        return (List<Object>) JSON.deserializeUntyped(RestContext.response.responseBody.toString());
    }

    private static Map<String, Object> responseObject() {
        return (Map<String, Object>) JSON.deserializeUntyped(RestContext.response.responseBody.toString());
    }

    @IsTest
    static void newAccountsAreCreated() {
        User integrationUser = IntegrationTestUtils.createIntegrationUser();
        System.runAs(integrationUser) {
            setRequest('POST', '/services/apexrest/v1/accounts',
                '[{"externalId":"ERP-1","name":"Acme","industry":"Technology"},{"externalId":"ERP-2","name":"Globex"}]');

            Test.startTest();
            AccountSyncResource.upsertAccounts();
            Test.stopTest();

            Assert.areEqual(200, RestContext.response.statusCode, 'All rows saved should return 200');
            Assert.areEqual('test-correlation-id', RestContext.response.headers.get('X-Correlation-Id'), 'The correlation id should be echoed back');
            List<Object> rows = responseRows();
            Assert.areEqual(2, rows.size(), 'One result per input row');
            Assert.isTrue((Boolean) ((Map<String, Object>) rows[0]).get('created'), 'The first account should be created');
        }
        Assert.areEqual(2, [SELECT COUNT() FROM Account WHERE External_Id__c IN ('ERP-1', 'ERP-2')], 'Both accounts should exist');
        Assert.areEqual(1, [SELECT COUNT() FROM Integration_Log__c WHERE Direction__c = 'Inbound' AND Correlation_Id__c = 'test-correlation-id'], 'The call should be logged');
    }

    @IsTest
    static void existingAccountIsUpdatedByExternalId() {
        User integrationUser = IntegrationTestUtils.createIntegrationUser();
        System.runAs(integrationUser) {
            insert new Account(Name = 'Old name', External_Id__c = 'ERP-7');
            setRequest('POST', '/services/apexrest/v1/accounts', '[{"externalId":"ERP-7","name":"New name"}]');

            AccountSyncResource.upsertAccounts();

            Map<String, Object> row = (Map<String, Object>) responseRows()[0];
            Assert.isFalse((Boolean) row.get('created'), 'The account should be updated, not created');
        }
        Assert.areEqual('New name', [SELECT Name FROM Account WHERE External_Id__c = 'ERP-7'].Name, 'The name should be updated');
    }

    @IsTest
    static void invalidRowsReturnPartialSuccess() {
        User integrationUser = IntegrationTestUtils.createIntegrationUser();
        System.runAs(integrationUser) {
            setRequest('POST', '/services/apexrest/v1/accounts',
                '[{"externalId":"ERP-3","name":"Valid"},{"externalId":"","name":"No id"},{"externalId":"ERP-3","name":"Duplicate"},{"externalId":"ERP-4"}]');

            AccountSyncResource.upsertAccounts();

            Assert.areEqual(207, RestContext.response.statusCode, 'Some rows failed, so 207 is expected');
            List<Object> rows = responseRows();
            Assert.isTrue((Boolean) ((Map<String, Object>) rows[0]).get('success'), 'The valid row should be saved');
            Assert.isTrue(String.valueOf(((Map<String, Object>) rows[1]).get('errors')).contains('externalId is required'), 'Missing id should be reported');
            Assert.isTrue(String.valueOf(((Map<String, Object>) rows[2]).get('errors')).contains('more than once'), 'Duplicate id should be reported');
            Assert.isTrue(String.valueOf(((Map<String, Object>) rows[3]).get('errors')).contains('name is required'), 'Missing name should be reported');
        }
    }

    @IsTest
    static void malformedJsonReturns400() {
        setRequest('POST', '/services/apexrest/v1/accounts', '{"externalId":"ERP-1"');

        AccountSyncResource.upsertAccounts();

        Assert.areEqual(400, RestContext.response.statusCode, 'Bad JSON should return 400');
        Assert.areEqual('INVALID_JSON', responseObject().get('errorCode'), 'The error code should explain the problem');
    }

    @IsTest
    static void unknownFieldsAreRejected() {
        setRequest('POST', '/services/apexrest/v1/accounts', '[{"externalId":"ERP-1","name":"Acme","creditLimit":5}]');

        AccountSyncResource.upsertAccounts();

        Assert.areEqual(400, RestContext.response.statusCode, 'Strict parsing should reject unknown fields');
    }

    @IsTest
    static void emptyAndOversizedRequestsReturn400() {
        setRequest('POST', '/services/apexrest/v1/accounts', '[]');
        AccountSyncResource.upsertAccounts();
        Assert.areEqual(400, RestContext.response.statusCode, 'An empty array should return 400');

        List<Map<String, String>> tooMany = new List<Map<String, String>>();
        for (Integer i = 0; i <= AccountSyncService.MAX_BATCH_SIZE; i++) {
            tooMany.add(new Map<String, String>{ 'externalId' => 'ERP-' + i, 'name' => 'Account ' + i });
        }
        setRequest('POST', '/services/apexrest/v1/accounts', JSON.serialize(tooMany));
        AccountSyncResource.upsertAccounts();
        Assert.areEqual(400, RestContext.response.statusCode, 'More than the batch limit should return 400');

        setRequest('POST', '/services/apexrest/v1/accounts', null);
        AccountSyncResource.upsertAccounts();
        Assert.areEqual(400, RestContext.response.statusCode, 'A missing body should return 400');
    }

    @IsTest
    static void getReturnsAccountOr404() {
        User integrationUser = IntegrationTestUtils.createIntegrationUser();
        System.runAs(integrationUser) {
            insert new Account(Name = 'Initech', External_Id__c = 'ERP 9');

            setRequest('GET', '/services/apexrest/v1/accounts/ERP%209', null);
            AccountSyncResource.getAccount();
            Assert.areEqual(200, RestContext.response.statusCode, 'An existing account should return 200');
            Assert.areEqual('Initech', responseObject().get('Name'), 'The account should be returned');

            setRequest('GET', '/services/apexrest/v1/accounts/ERP-404', null);
            AccountSyncResource.getAccount();
            Assert.areEqual(404, RestContext.response.statusCode, 'An unknown id should return 404');

            setRequest('GET', '/services/apexrest/v1/accounts', null);
            AccountSyncResource.getAccount();
            Assert.areEqual(400, RestContext.response.statusCode, 'A missing id should return 400');
        }
    }
}
