/**
 * Sends a callout asynchronously and retries temporary failures with
 * exponential backoff (1, 2, 4 ... minutes, capped at 10) using a delayed
 * Queueable. Permanent failures (for example 400 or 404) are not retried.
 *
 *   System.enqueueJob(new RetryableCalloutJob(
 *       new HttpCalloutService.CalloutRequest('POST', 'callout:Billing_API/v1/invoices', body)));
 */
public with sharing class RetryableCalloutJob implements Queueable, Database.AllowsCallouts {

    public static final Integer MAX_ATTEMPTS = 3;
    private static final Integer MAX_DELAY_MINUTES = 10;

    private final HttpCalloutService.CalloutRequest request;

    public RetryableCalloutJob(HttpCalloutService.CalloutRequest request) {
        this.request = request;
    }

    public void execute(QueueableContext context) {
        HttpCalloutService.CalloutResult result = HttpCalloutService.send(request);
        IntegrationLogger.flush();

        if (shouldRetry(result, request.attempt)) {
            request.attempt++;
            System.enqueueJob(new RetryableCalloutJob(request), backoffMinutes(request.attempt));
        }
    }

    @TestVisible
    private static Boolean shouldRetry(HttpCalloutService.CalloutResult result, Integer attempt) {
        return !result.success && result.retryable && attempt < MAX_ATTEMPTS;
    }

    @TestVisible
    private static Integer backoffMinutes(Integer attempt) {
        Integer minutes = Math.pow(2, attempt - 1).intValue();
        return Math.min(minutes, MAX_DELAY_MINUTES);
    }
}
