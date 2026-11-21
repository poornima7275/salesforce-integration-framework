/**
 * Inbound REST API for an external system (ERP, billing, MDM) to keep
 * Accounts in sync.
 *
 *   POST /services/apexrest/v1/accounts            body: [ { "externalId": "ERP-1001", "name": "Acme" } ]
 *   GET  /services/apexrest/v1/accounts/ERP-1001
 *
 * Status codes: 200 all rows saved, 207 some rows failed, 400 bad request,
 * 404 not found. Every call is logged with its correlation id.
 */
@RestResource(urlMapping='/v1/accounts/*')
global with sharing class AccountSyncResource {

    private static final String BASE_PATH = '/v1/accounts';

    @HttpPost
    global static void upsertAccounts() {
        RestRequest request = RestContext.request;
        String correlationId = correlationIdFrom(request);
        String requestBody = request.requestBody == null ? null : request.requestBody.toString();

        Integer statusCode = 200;
        Object responseBody;
        try {
            if (String.isBlank(requestBody)) {
                throw new AccountSyncService.SyncException('The request body is empty');
            }
            List<AccountSyncService.AccountPayload> payloads = (List<AccountSyncService.AccountPayload>)
                JSON.deserializeStrict(requestBody, List<AccountSyncService.AccountPayload>.class);
            List<AccountSyncService.SyncResult> results = AccountSyncService.upsertAccounts(payloads);
            for (AccountSyncService.SyncResult result : results) {
                if (!result.success) {
                    statusCode = 207;
                }
            }
            responseBody = results;
        } catch (JSONException e) {
            statusCode = 400;
            responseBody = errorBody('INVALID_JSON', 'The body must be a JSON array of accounts: ' + e.getMessage());
        } catch (AccountSyncService.SyncException e) {
            statusCode = 400;
            responseBody = errorBody('INVALID_REQUEST', e.getMessage());
        }

        respond(statusCode, responseBody, correlationId, 'POST', requestBody);
    }

    @HttpGet
    global static void getAccount() {
        RestRequest request = RestContext.request;
        String correlationId = correlationIdFrom(request);
        String externalId = EncodingUtil.urlDecode(request.requestURI.substringAfterLast('/'), 'UTF-8');

        Integer statusCode;
        Object responseBody;
        if (String.isBlank(externalId) || externalId == 'accounts') {
            statusCode = 400;
            responseBody = errorBody('INVALID_REQUEST', 'Add the external id to the URL, for example /v1/accounts/ERP-1001');
        } else {
            Account match = AccountSyncService.findByExternalId(externalId);
            if (match == null) {
                statusCode = 404;
                responseBody = errorBody('NOT_FOUND', 'No account with externalId ' + externalId);
            } else {
                statusCode = 200;
                responseBody = match;
            }
        }

        respond(statusCode, responseBody, correlationId, 'GET', null);
    }

    private static void respond(Integer statusCode, Object body, String correlationId, String method, String requestBody) {
        String payload = JSON.serialize(body, true);
        RestResponse response = RestContext.response;
        response.statusCode = statusCode;
        response.addHeader('Content-Type', 'application/json');
        response.addHeader('X-Correlation-Id', correlationId);
        response.responseBody = Blob.valueOf(payload);

        IntegrationLogger.logInbound(BASE_PATH, method, statusCode, requestBody, payload, correlationId);
        IntegrationLogger.flush();
    }

    private static String correlationIdFrom(RestRequest request) {
        String incoming = request.headers == null ? null : request.headers.get('X-Correlation-Id');
        return String.isBlank(incoming) ? HttpCalloutService.newCorrelationId() : incoming.left(64);
    }

    private static Map<String, String> errorBody(String code, String message) {
        return new Map<String, String>{ 'errorCode' => code, 'message' => message };
    }
}
