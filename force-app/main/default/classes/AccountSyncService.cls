/**
 * Business logic behind the inbound Account API.
 * Upserts by Account.External_Id__c in user mode (object, field and sharing
 * security enforced) and returns one result per input row, so a caller can
 * see exactly which rows failed and why (partial success).
 */
public with sharing class AccountSyncService {

    public static final Integer MAX_BATCH_SIZE = 200;
    private static final Integer MAX_EXTERNAL_ID_LENGTH = 50;

    public class SyncException extends Exception {}

    public class AccountPayload {
        public String externalId;
        public String name;
        public String industry;
        public String phone;
        public String website;
    }

    public class SyncResult {
        public Integer index;
        public String externalId;
        public Boolean success = false;
        public Boolean created = false;
        public String id;
        public List<String> errors = new List<String>();
    }

    public static List<SyncResult> upsertAccounts(List<AccountPayload> payloads) {
        if (payloads == null || payloads.isEmpty()) {
            throw new SyncException('The request must contain at least one account');
        }
        if (payloads.size() > MAX_BATCH_SIZE) {
            throw new SyncException('A maximum of ' + MAX_BATCH_SIZE + ' accounts can be sent in one request');
        }

        List<SyncResult> results = new List<SyncResult>();
        List<Account> accounts = new List<Account>();
        List<Integer> positions = new List<Integer>();
        Set<String> seenIds = new Set<String>();

        for (Integer i = 0; i < payloads.size(); i++) {
            AccountPayload payload = payloads[i];
            SyncResult result = new SyncResult();
            result.index = i;
            result.externalId = payload == null ? null : payload.externalId;
            results.add(result);

            result.errors.addAll(validate(payload, seenIds));
            if (!result.errors.isEmpty()) {
                continue;
            }
            seenIds.add(payload.externalId.toLowerCase());
            accounts.add(new Account(
                External_Id__c = payload.externalId,
                Name = payload.name,
                Industry = payload.industry,
                Phone = payload.phone,
                Website = payload.website
            ));
            positions.add(i);
        }

        if (!accounts.isEmpty()) {
            List<Database.UpsertResult> upserts = Database.upsert(accounts, Account.External_Id__c, false, AccessLevel.USER_MODE);
            for (Integer j = 0; j < upserts.size(); j++) {
                SyncResult result = results[positions[j]];
                result.success = upserts[j].isSuccess();
                result.created = upserts[j].isCreated();
                result.id = upserts[j].getId();
                for (Database.Error error : upserts[j].getErrors()) {
                    result.errors.add(error.getMessage());
                }
            }
        }
        return results;
    }

    public static Account findByExternalId(String externalId) {
        List<Account> accounts = [
            SELECT Id, Name, External_Id__c, Industry, Phone, Website, LastModifiedDate
            FROM Account
            WHERE External_Id__c = :externalId
            WITH USER_MODE
            LIMIT 1
        ];
        return accounts.isEmpty() ? null : accounts[0];
    }

    private static List<String> validate(AccountPayload payload, Set<String> seenIds) {
        List<String> errors = new List<String>();
        if (payload == null) {
            errors.add('Account is empty');
            return errors;
        }
        if (String.isBlank(payload.externalId)) {
            errors.add('externalId is required');
        } else if (payload.externalId.length() > MAX_EXTERNAL_ID_LENGTH) {
            errors.add('externalId must be ' + MAX_EXTERNAL_ID_LENGTH + ' characters or fewer');
        } else if (seenIds.contains(payload.externalId.toLowerCase())) {
            errors.add('externalId appears more than once in this request');
        }
        if (String.isBlank(payload.name)) {
            errors.add('name is required');
        }
        return errors;
    }
}
