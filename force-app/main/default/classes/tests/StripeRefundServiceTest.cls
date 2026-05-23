@isTest
private class StripeRefundServiceTest {

    @TestSetup
    static void setup() {
        Id paRtId = [SELECT Id FROM RecordType WHERE SObjectType = 'Account' AND IsPersonType = true LIMIT 1].Id;

        Account pa = new Account(
            RecordTypeId = paRtId,
            LastName     = 'Refundee',
            PersonEmail  = 'refundee@example.com'
        );
        insert pa;

        insert new GiftTransaction(
            DonorId             = pa.Id,
            OriginalAmount      = 100.00,
            TransactionDate     = Date.today(),
            Status              = 'Paid',
            PaymentMethod       = 'Stripe',
            Stripe_Charge_Id__c = 'ch_refund_001',
            Name                = 'Refundee-Test'
        );
    }

    // ── GiftRefund Creation ──────────────────────────────────────────────────

    @isTest
    static void process_matchingGiftTransaction_createsGiftRefundWithAllFields() {
        Test.startTest();
        StripeRefundService.process(new List<stripeGC__Stripe_Event__c>{
            refundEvent('evt_r001', 'ch_refund_001', 5000)
        });
        Test.stopTest();

        GiftTransaction gt = [SELECT Id FROM GiftTransaction WHERE Stripe_Charge_Id__c = 'ch_refund_001'];
        List<GiftRefund> refunds = [SELECT Status, Amount, Date FROM GiftRefund WHERE GiftTransactionId = :gt.Id];

        Assert.areEqual(1,           refunds.size());
        Assert.areEqual('Completed', refunds[0].Status);
        Assert.areEqual(50.00,       refunds[0].Amount);
        Assert.isNotNull(refunds[0].Date);
    }

    @isTest
    static void process_unknownChargeId_logsErrorAndCreatesNoGiftRefund() {
        Test.startTest();
        StripeRefundService.process(new List<stripeGC__Stripe_Event__c>{
            refundEvent('evt_r002', 'ch_does_not_exist', 2000)
        });
        Test.stopTest();

        Assert.isTrue([SELECT Id FROM GiftRefund].isEmpty());
    }

    @isTest
    static void process_malformedJson_catchesExceptionAndContinues() {
        stripeGC__Stripe_Event__c badEvt = new stripeGC__Stripe_Event__c(
            stripeGC__stripe_event_id__c = 'evt_r003',
            stripeGC__event_name__c      = 'charge.refunded',
            stripeGC__request_body__c    = 'not-valid-json{{{'
        );

        Test.startTest();
        try {
            StripeRefundService.process(new List<stripeGC__Stripe_Event__c>{ badEvt });
        } catch (Exception ex) {
            Assert.fail('Service must not surface exceptions — all errors are caught internally');
        }
        Test.stopTest();
    }

    @isTest
    static void process_batchMixed_createsGiftRefundOnlyForMatchedCharges() {
        Account pa = [SELECT Id FROM Account WHERE PersonEmail = 'refundee@example.com' LIMIT 1];
        insert new GiftTransaction(
            DonorId             = pa.Id,
            OriginalAmount      = 75.00,
            TransactionDate     = Date.today(),
            Status              = 'Paid',
            PaymentMethod       = 'Stripe',
            Stripe_Charge_Id__c = 'ch_refund_002',
            Name                = 'Refundee-Test2'
        );

        Test.startTest();
        StripeRefundService.process(new List<stripeGC__Stripe_Event__c>{
            refundEvent('evt_r004', 'ch_refund_001', 10000),
            refundEvent('evt_r005', 'ch_refund_002', 7500),
            refundEvent('evt_r006', 'ch_no_match',   5000)
        });
        Test.stopTest();

        Assert.areEqual(2, [SELECT Id FROM GiftRefund].size());
    }

    @isTest
    static void process_amountConvertedFromCentsCorrectly() {
        Test.startTest();
        StripeRefundService.process(new List<stripeGC__Stripe_Event__c>{
            refundEvent('evt_r007', 'ch_refund_001', 7575)
        });
        Test.stopTest();

        GiftTransaction gt = [SELECT Id FROM GiftTransaction WHERE Stripe_Charge_Id__c = 'ch_refund_001'];
        GiftRefund refund = [SELECT Amount FROM GiftRefund WHERE GiftTransactionId = :gt.Id];
        Assert.areEqual(75.75, refund.Amount);
    }

    @isTest
    static void process_emptyEventsList_completesWithNoSideEffects() {
        Test.startTest();
        StripeRefundService.process(new List<stripeGC__Stripe_Event__c>());
        Test.stopTest();

        Assert.isTrue([SELECT Id FROM GiftRefund].isEmpty());
    }

    // ── Helpers ──────────────────────────────────────────────────────────────

    private static stripeGC__Stripe_Event__c refundEvent(
        String eventId, String chargeId, Integer amountRefunded
    ) {
        return new stripeGC__Stripe_Event__c(
            stripeGC__stripe_event_id__c = eventId,
            stripeGC__event_name__c      = 'charge.refunded',
            stripeGC__request_body__c    = JSON.serialize(new Map<String, Object>{
                'data' => new Map<String, Object>{
                    'object' => new Map<String, Object>{
                        'id'              => chargeId,
                        'amount_refunded' => amountRefunded,
                        'created'         => (Long)(DateTime.now().getTime() / 1000)
                    }
                }
            })
        );
    }
}