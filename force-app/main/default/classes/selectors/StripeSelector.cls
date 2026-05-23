public without sharing class StripeSelector {

    public static Set<String> getProcessedEventIds(Set<String> eventIds) {
        Set<String> processed = new Set<String>();
        for (GiftTransaction gt : [
            SELECT Stripe_Event_Id__c
            FROM   GiftTransaction
            WHERE  Stripe_Event_Id__c IN :eventIds
        ]) {
            processed.add(gt.Stripe_Event_Id__c);
        }
        return processed;
    }

    public static List<Account> getPersonAccounts(Set<String> customerIds, Set<String> emails) {
        return [
            SELECT Id, PersonEmail, stripeGC__Customer_Id__c
            FROM   Account
            WHERE  IsPersonAccount = true
            AND   (stripeGC__Customer_Id__c IN :customerIds OR PersonEmail IN :emails)
        ];
    }

    public static List<Product2> getActiveProductsBySkus(Set<String> skus) {
        return [
            SELECT Id, StockKeepingUnit
            FROM   Product2
            WHERE  IsActive = true
            AND    StockKeepingUnit IN :skus
        ];
    }

    public static List<GiftTransaction> getGiftTransactionsByChargeIds(Set<String> chargeIds) {
        return [
            SELECT Id, Stripe_Charge_Id__c
            FROM   GiftTransaction
            WHERE  Stripe_Charge_Id__c IN :chargeIds
        ];
    }

    public static Id getPersonAccountRecordTypeId() {
        List<RecordType> rts = [
            SELECT Id
            FROM   RecordType
            WHERE  SObjectType = 'Account' AND IsPersonType = true
            LIMIT  1
        ];
        return rts.isEmpty() ? null : rts[0].Id;
    }
}