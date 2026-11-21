/**
 * Single entry point for outbound REST callouts.
 *
 * - Adds a correlation id header so a call can be traced across systems
 * - Classifies failures as retryable (timeouts, 408, 429, 5xx) or permanent
 * - Buffers a log entry for every call; call IntegrationLogger.flush() once
 *   all callouts in the transaction are done
 *
 * Use a Named Credential for the endpoint (for example 'callout:Billing_API/v1/invoices')
 * so that no URL or secret is stored in code.
 */
public with sharing class HttpCalloutService {

    private static final Set<Integer> RETRYABLE_STATUS_CODES = new Set<Integer>{ 408, 429, 500, 502, 503, 504 };

    public class CalloutRequest {
        public String endpoint;
        public String method = 'GET';
        public String body;
        public Map<String, String> headers = new Map<String, String>();
        public Integer timeoutMs = 20000;
        public String correlationId;
        public Integer attempt = 1;

        public CalloutRequest(String method, String endpoint, String body) {
            this.method = method;
            this.endpoint = endpoint;
            this.body = body;
        }
    }

    public class CalloutResult {
        @AuraEnabled public Boolean success = false;
        @AuraEnabled public Boolean retryable = false;
        @AuraEnabled public Integer statusCode;
        @AuraEnabled public String body;
        @AuraEnabled public String errorMessage;
        @AuraEnabled public Long durationMs;
    }

    public static CalloutResult send(CalloutRequest request) {
        if (request == null || String.isBlank(request.endpoint) || String.isBlank(request.method)) {
            throw new IllegalArgumentException('A callout needs an endpoint and an HTTP method');
        }
        if (String.isBlank(request.correlationId)) {
            request.correlationId = newCorrelationId();
        }

        HttpRequest http = new HttpRequest();
        http.setEndpoint(request.endpoint);
        http.setMethod(request.method.toUpperCase());
        http.setTimeout(request.timeoutMs);
        http.setHeader('Content-Type', 'application/json');
        http.setHeader('Accept', 'application/json');
        http.setHeader('X-Correlation-Id', request.correlationId);
        for (String name : request.headers.keySet()) {
            http.setHeader(name, request.headers.get(name));
        }
        if (request.body != null) {
            http.setBody(request.body);
        }

        CalloutResult result = new CalloutResult();
        Long started = System.currentTimeMillis();
        try {
            HttpResponse response = new Http().send(http);
            result.statusCode = response.getStatusCode();
            result.body = response.getBody();
            result.success = result.statusCode >= 200 && result.statusCode < 300;
            result.retryable = RETRYABLE_STATUS_CODES.contains(result.statusCode);
            if (!result.success) {
                result.errorMessage = 'HTTP ' + result.statusCode + ' ' + response.getStatus();
            }
        } catch (CalloutException e) {
            // Timeouts and connection errors are usually temporary
            result.retryable = true;
            result.errorMessage = e.getMessage();
        }
        result.durationMs = System.currentTimeMillis() - started;

        IntegrationLogger.logOutbound(request, result);
        return result;
    }

    public static String newCorrelationId() {
        return EncodingUtil.convertToHex(Crypto.generateAesKey(128)).left(32);
    }
}
