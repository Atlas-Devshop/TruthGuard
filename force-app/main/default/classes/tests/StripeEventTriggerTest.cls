@isTest
private class StripeEventTriggerTest {

    @isTest
    static void insert_stripeEvent_triggerFiresWithoutError() {
        stripeGC__Stripe_Event__c evt = new stripeGC__Stripe_Event__c(
            stripeGC__stripe_event_id__c = 'evt_trigger_test',
            stripeGC__event_name__c      = 'customer.created',
            stripeGC__request_body__c    = '{}'
        );

        Test.startTest();
        try {
            insert evt;
        } catch (Exception ex) {
            Assert.fail('Trigger must not surface exceptions: ' + ex.getMessage());
        }
        Test.stopTest();
    }
}