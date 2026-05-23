@isTest
private class StripePaymentServiceTest {

    @TestSetup
    static void setup() {
        Id paRtId = [SELECT Id FROM RecordType WHERE SObjectType = 'Account' AND IsPersonType = true LIMIT 1].Id;

        Account pa = new Account(
            RecordTypeId             = paRtId,
            LastName                 = 'Smith',
            PersonEmail              = 'john.smith@example.com',
            stripeGC__Customer_Id__c = 'cus_existing_001'
        );
        insert pa;

        insert new Product2(Name = 'FOOD', StockKeepingUnit = 'FOOD', IsActive = true);
    }

    // ── Donor Resolution ─────────────────────────────────────────────────────

    @isTest
    static void process_donorMatchedByCustomerId_createsGiftTransaction() {
        Test.startTest();
        StripePaymentService.process(new List<stripeGC__Stripe_Event__c>{
            paymentEvent('evt_001', 'cus_existing_001', 5000, 'ch_001', 'john.smith@example.com', 'John Smith', null)
        });
        Test.stopTest();

        List<GiftTransaction> gts = [SELECT OriginalAmount, Status, PaymentMethod FROM GiftTransaction WHERE Stripe_Event_Id__c = 'evt_001'];
        Assert.areEqual(1,        gts.size());
        Assert.areEqual(50.00,    gts[0].OriginalAmount);
        Assert.areEqual('Paid',   gts[0].Status);
        Assert.areEqual('Stripe', gts[0].PaymentMethod);
    }

    @isTest
    static void process_donorMatchedByEmail_backfillsStripeCustomerId() {
        Id paRtId = [SELECT Id FROM RecordType WHERE SObjectType = 'Account' AND IsPersonType = true LIMIT 1].Id;
        Account emailOnlyPa = new Account(RecordTypeId = paRtId, LastName = 'Jones', PersonEmail = 'jones@example.com');
        insert emailOnlyPa;

        Test.startTest();
        StripePaymentService.process(new List<stripeGC__Stripe_Event__c>{
            paymentEvent('evt_002', 'cus_new_for_jones', 3000, 'ch_002', 'jones@example.com', 'Bob Jones', null)
        });
        Test.stopTest();

        Assert.areEqual('cus_new_for_jones', [SELECT stripeGC__Customer_Id__c FROM Account WHERE Id = :emailOnlyPa.Id].stripeGC__Customer_Id__c);
        Assert.areEqual(1, [SELECT Id FROM GiftTransaction WHERE Stripe_Event_Id__c = 'evt_002'].size());
    }

    @isTest
    static void process_noDonorFound_autoCreatesPersonAccount() {
        Test.startTest();
        StripePaymentService.process(new List<stripeGC__Stripe_Event__c>{
            paymentEvent('evt_003', 'cus_brand_new', 2000, 'ch_003', 'newdonor@example.com', 'Jane Doe', null)
        });
        Test.stopTest();

        List<Account> created = [SELECT FirstName, LastName, PersonEmail, stripeGC__Customer_Id__c FROM Account WHERE PersonEmail = 'newdonor@example.com' AND IsPersonAccount = true];
        Assert.areEqual(1,                    created.size());
        Assert.areEqual('Jane',               created[0].FirstName);
        Assert.areEqual('Doe',                created[0].LastName);
        Assert.areEqual('cus_brand_new',      created[0].stripeGC__Customer_Id__c);
        Assert.areEqual(1, [SELECT Id FROM GiftTransaction WHERE Stripe_Event_Id__c = 'evt_003'].size());
    }

    @isTest
    static void process_sameBatchSameUnknownEmail_createsOnlyOnePersonAccount() {
        Test.startTest();
        StripePaymentService.process(new List<stripeGC__Stripe_Event__c>{
            paymentEvent('evt_004a', 'cus_batch', 1000, 'ch_004a', 'batch@example.com', 'Batch User', null),
            paymentEvent('evt_004b', 'cus_batch', 2000, 'ch_004b', 'batch@example.com', 'Batch User', null)
        });
        Test.stopTest();

        Assert.areEqual(1, [SELECT Id FROM Account WHERE PersonEmail = 'batch@example.com' AND IsPersonAccount = true].size());
        Assert.areEqual(2, [SELECT Id FROM GiftTransaction WHERE Stripe_Event_Id__c IN ('evt_004a', 'evt_004b')].size());
    }

    @isTest
    static void process_noEmailAndNoCustomerId_logsErrorAndSkips() {
        Test.startTest();
        StripePaymentService.process(new List<stripeGC__Stripe_Event__c>{
            paymentEventNoIdentity('evt_005', 5000, 'ch_005')
        });
        Test.stopTest();

        Assert.isTrue([SELECT Id FROM GiftTransaction WHERE Stripe_Event_Id__c = 'evt_005'].isEmpty());
    }

    // ── Idempotency ──────────────────────────────────────────────────────────

    @isTest
    static void process_duplicateEventId_doesNotCreateSecondGiftTransaction() {
        Account pa = [SELECT Id FROM Account WHERE PersonEmail = 'john.smith@example.com' LIMIT 1];
        insert new GiftTransaction(
            DonorId            = pa.Id,
            OriginalAmount     = 50.00,
            TransactionDate    = Date.today(),
            Status             = 'Paid',
            PaymentMethod      = 'Stripe',
            Stripe_Event_Id__c = 'evt_dup',
            Name               = 'Smith-Test'
        );

        Test.startTest();
        StripePaymentService.process(new List<stripeGC__Stripe_Event__c>{
            paymentEvent('evt_dup', 'cus_existing_001', 5000, 'ch_dup', 'john.smith@example.com', 'John Smith', null)
        });
        Test.stopTest();

        Assert.areEqual(1, [SELECT Id FROM GiftTransaction WHERE Stripe_Event_Id__c = 'evt_dup'].size());
    }

    // ── Product Resolution ───────────────────────────────────────────────────

    @isTest
    static void process_knownProduct_createsGiftTransactionLineWithCorrectUnitPrice() {
        Test.startTest();
        StripePaymentService.process(new List<stripeGC__Stripe_Event__c>{
            paymentEvent('evt_006', 'cus_existing_001', 6000, 'ch_006', 'john.smith@example.com', 'John Smith', 'FOOD:3')
        });
        Test.stopTest();

        GiftTransaction gt = [SELECT Id FROM GiftTransaction WHERE Stripe_Event_Id__c = 'evt_006'];
        List<Gift_Transaction_Line__c> lines = [SELECT Quantity__c, Unit_Price__c FROM Gift_Transaction_Line__c WHERE Gift_Transaction__c = :gt.Id];
        Assert.areEqual(1,     lines.size());
        Assert.areEqual(3,     lines[0].Quantity__c);
        Assert.areEqual(20.00, lines[0].Unit_Price__c);
    }

    @isTest
    static void process_unknownSku_autoCreatesProduct2AndGiftTransactionLine() {
        Test.startTest();
        StripePaymentService.process(new List<stripeGC__Stripe_Event__c>{
            paymentEvent('evt_007', 'cus_existing_001', 4000, 'ch_007', 'john.smith@example.com', 'John Smith', 'NEWPROD:2')
        });
        Test.stopTest();

        Assert.areEqual(1, [SELECT Id FROM Product2 WHERE StockKeepingUnit = 'NEWPROD'].size());
        GiftTransaction gt = [SELECT Id FROM GiftTransaction WHERE Stripe_Event_Id__c = 'evt_007'];
        Assert.areEqual(1, [SELECT Id FROM Gift_Transaction_Line__c WHERE Gift_Transaction__c = :gt.Id].size());
    }

    @isTest
    static void process_multipleProductsInDescription_createsOneLinePerProduct() {
        insert new Product2(Name = 'MED', StockKeepingUnit = 'MED', IsActive = true);

        Test.startTest();
        StripePaymentService.process(new List<stripeGC__Stripe_Event__c>{
            paymentEvent('evt_008', 'cus_existing_001', 9000, 'ch_008', 'john.smith@example.com', 'John Smith', 'FOOD:2;MED:1')
        });
        Test.stopTest();

        GiftTransaction gt = [SELECT Id FROM GiftTransaction WHERE Stripe_Event_Id__c = 'evt_008'];
        Assert.areEqual(2, [SELECT Id FROM Gift_Transaction_Line__c WHERE Gift_Transaction__c = :gt.Id].size());
    }

    @isTest
    static void process_blankDescription_createsGiftTransactionWithNoLines() {
        Test.startTest();
        StripePaymentService.process(new List<stripeGC__Stripe_Event__c>{
            paymentEvent('evt_009', 'cus_existing_001', 5000, 'ch_009', 'john.smith@example.com', 'John Smith', null)
        });
        Test.stopTest();

        GiftTransaction gt = [SELECT Id FROM GiftTransaction WHERE Stripe_Event_Id__c = 'evt_009'];
        Assert.isNotNull(gt);
        Assert.isTrue([SELECT Id FROM Gift_Transaction_Line__c WHERE Gift_Transaction__c = :gt.Id].isEmpty());
    }

    // ── Handler Routing ──────────────────────────────────────────────────────

    @isTest
    static void handleNewEvents_unknownEventType_isIgnoredSilently() {
        stripeGC__Stripe_Event__c evt = new stripeGC__Stripe_Event__c(
            stripeGC__stripe_event_id__c = 'evt_unknown',
            stripeGC__event_name__c      = 'customer.created',
            stripeGC__request_body__c    = '{}'
        );

        Test.startTest();
        StripeEventHandler.handleNewEvents(new List<stripeGC__Stripe_Event__c>{ evt });
        Test.stopTest();

        Assert.isTrue([SELECT Id FROM GiftTransaction WHERE Stripe_Event_Id__c = 'evt_unknown'].isEmpty());
    }

    @isTest
    static void handleNewEvents_mixedBatch_routesEachEventToCorrectService() {
        Account pa = [SELECT Id FROM Account WHERE PersonEmail = 'john.smith@example.com' LIMIT 1];
        insert new GiftTransaction(
            DonorId             = pa.Id,
            OriginalAmount      = 50.00,
            TransactionDate     = Date.today(),
            Status              = 'Paid',
            PaymentMethod       = 'Stripe',
            Stripe_Charge_Id__c = 'ch_mixed_refund',
            Name                = 'Smith-Mixed'
        );

        stripeGC__Stripe_Event__c payEvt = paymentEvent(
            'evt_mixed_pay', 'cus_existing_001', 5000, 'ch_mixed_pay',
            'john.smith@example.com', 'John Smith', null
        );
        stripeGC__Stripe_Event__c refundEvt = new stripeGC__Stripe_Event__c(
            stripeGC__stripe_event_id__c = 'evt_mixed_refund',
            stripeGC__event_name__c      = 'charge.refunded',
            stripeGC__request_body__c    = JSON.serialize(new Map<String, Object>{
                'data' => new Map<String, Object>{
                    'object' => new Map<String, Object>{
                        'id'              => 'ch_mixed_refund',
                        'amount_refunded' => 5000,
                        'created'         => (Long)(DateTime.now().getTime() / 1000)
                    }
                }
            })
        );

        Test.startTest();
        StripeEventHandler.handleNewEvents(new List<stripeGC__Stripe_Event__c>{ payEvt, refundEvt });
        Test.stopTest();

        Assert.areEqual(1, [SELECT Id FROM GiftTransaction WHERE Stripe_Event_Id__c = 'evt_mixed_pay'].size());
        GiftTransaction gt = [SELECT Id FROM GiftTransaction WHERE Stripe_Charge_Id__c = 'ch_mixed_refund'];
        Assert.areEqual(1, [SELECT Id FROM GiftRefund WHERE GiftTransactionId = :gt.Id].size());
    }

    // ── Helpers ──────────────────────────────────────────────────────────────

    private static stripeGC__Stripe_Event__c paymentEvent(
        String eventId, String customerId, Integer amountCents,
        String chargeId, String email, String cardName, String description
    ) {
        return new stripeGC__Stripe_Event__c(
            stripeGC__stripe_event_id__c = eventId,
            stripeGC__event_name__c      = 'payment_intent.succeeded',
            stripeGC__request_body__c    = JSON.serialize(new Map<String, Object>{
                'data' => new Map<String, Object>{
                    'object' => new Map<String, Object>{
                        'amount'        => amountCents,
                        'latest_charge' => chargeId,
                        'customer'      => customerId,
                        'description'   => description,
                        'created'       => 1716393600,
                        'receipt_email' => email,
                        'charges'       => new Map<String, Object>{
                            'data' => new List<Object>{
                                new Map<String, Object>{
                                    'billing_details' => new Map<String, Object>{
                                        'name'  => cardName,
                                        'email' => email
                                    }
                                }
                            }
                        }
                    }
                }
            })
        );
    }

    private static stripeGC__Stripe_Event__c paymentEventNoIdentity(
        String eventId, Integer amountCents, String chargeId
    ) {
        return new stripeGC__Stripe_Event__c(
            stripeGC__stripe_event_id__c = eventId,
            stripeGC__event_name__c      = 'payment_intent.succeeded',
            stripeGC__request_body__c    = JSON.serialize(new Map<String, Object>{
                'data' => new Map<String, Object>{
                    'object' => new Map<String, Object>{
                        'amount'        => amountCents,
                        'latest_charge' => chargeId,
                        'customer'      => null,
                        'description'   => null,
                        'created'       => 1716393600,
                        'receipt_email' => null
                    }
                }
            })
        );
    }
}