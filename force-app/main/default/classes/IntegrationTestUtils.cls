@IsTest
public class IntegrationTestUtils {

    /** Returns a fixed response, or throws a CalloutException to simulate a timeout. */
    public class MockResponse implements HttpCalloutMock {
        private final Integer statusCode;
        private final String body;
        private final Boolean throwTimeout;
        public HttpRequest lastRequest;

        public MockResponse(Integer statusCode, String body) {
            this.statusCode = statusCode;
            this.body = body;
            this.throwTimeout = false;
        }

        public MockResponse(Boolean throwTimeout) {
            this.throwTimeout = throwTimeout;
        }

        public HttpResponse respond(HttpRequest request) {
            lastRequest = request;
            if (throwTimeout) {
                throw new CalloutException('Read timed out');
            }
            HttpResponse response = new HttpResponse();
            response.setStatusCode(statusCode);
            response.setStatus(statusCode == 200 ? 'OK' : 'Error');
            response.setBody(body);
            return response;
        }
    }

    /** A Standard User with the Integration Framework User permission set. */
    public static User createIntegrationUser() {
        Profile profile = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1];
        String unique = String.valueOf(Crypto.getRandomInteger()).replace('-', '');
        User user = new User(
            Alias = 'intg',
            Email = 'integration.user@example.com',
            EmailEncodingKey = 'UTF-8',
            LastName = 'Integration User',
            LanguageLocaleKey = 'en_US',
            LocaleSidKey = 'en_US',
            ProfileId = profile.Id,
            TimeZoneSidKey = 'Europe/Dublin',
            Username = 'integration.' + unique + '@example.com.sif'
        );
        insert user;
        PermissionSet permissionSet = [SELECT Id FROM PermissionSet WHERE Name = 'Integration_Framework_User' LIMIT 1];
        insert new PermissionSetAssignment(AssigneeId = user.Id, PermissionSetId = permissionSet.Id);
        return user;
    }
}
