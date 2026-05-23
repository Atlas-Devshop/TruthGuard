@isTest
private class StripePayloadTest {

    // ── StripePaymentPayload ─────────────────────────────────────────────────

    @isTest
    static void parse_fullPayload_mapsAllFields() {
        stripeGC__Stripe_Event__c evt = paymentEvent(
            'evt_001', 'cus_001', 5000, 'ch_001',
            'john.smith@example.com', 'John Smith', 'FOOD:2;MED:1'
        );

        StripePaymentPayload p = StripePaymentPayload.parse(evt);

        Assert.areEqual('evt_001',                   p.eventId);
        Assert.areEqual(50.00,                       p.amount);
        Assert.areEqual('ch_001',                    p.chargeId);
        Assert.areEqual('cus_001',                   p.stripeCustomerId);
        Assert.areEqual('john.smith@example.com',    p.email);
        Assert.areEqual('John',                      p.firstName);
        Assert.areEqual('Smith',                     p.lastName);
        Assert.areEqual(0,                           p.fee);
        Assert.isNotNull(p.transactionDate);
    }

    @isTest
    static void parse_multiWordName_firstNameGetsAllWordsBeforeLast() {
        stripeGC__Stripe_Event__c evt = paymentEvent(
            'evt_002', 'cus_002', 2000, 'ch_002',
            'mw@example.com', 'Mary Jane Watson', null
        );

        StripePaymentPayload p = StripePaymentPayload.parse(evt);

        Assert.areEqual('Mary Jane', p.firstName);
        Assert.areEqual('Watson',    p.lastName);
    }

    @isTest
    static void parse_singleWordName_firstNameIsNull() {
        stripeGC__Stripe_Event__c evt = paymentEvent(
            'evt_003', 'cus_003', 1000, 'ch_003',
            'kyle@example.com', 'Kyle', null
        );

        StripePaymentPayload p = StripePaymentPayload.parse(evt);

        Assert.isNull(p.firstName);
        Assert.areEqual('Kyle', p.lastName);
    }

    @isTest
    static void parse_noCardName_derivesLastNameFromEmail() {
        stripeGC__Stripe_Event__c evt = paymentEventNoBillingName(
            'evt_004', 'cus_004', 3000, 'ch_004', 'jane.doe@example.com', null
        );

        StripePaymentPayload p = StripePaymentPayload.parse(evt);

        Assert.isNull(p.firstName);
        Assert.areEqual('Janedoe', p.lastName);
    }

    @isTest
    static void parse_noCardNameNoEmail_lastNameIsUnknown() {
        stripeGC__Stripe_Event__c evt = paymentEventNoIdentity(
            'evt_005', 'cus_005', 1000, 'ch_005'
        );

        StripePaymentPayload p = StripePaymentPayload.parse(evt);

        Assert.isNull(p.firstName);
        Assert.areEqual('Unknown', p.lastName);
    }

    @isTest
    static void parse_receiptEmailNull_fallsBackToBillingDetailsEmail() {
        stripeGC__Stripe_Event__c evt = paymentEventNoBillingName(
            'evt_006', 'cus_006', 4000, 'ch_006', 'fallback@example.com', null
        );

        StripePaymentPayload p = StripePaymentPayload.parse(evt);

        Assert.areEqual('fallback@example.com', p.email);
    }

    @isTest
    static void parse_blankRequestBody_returnsNull() {
        stripeGC__Stripe_Event__c evt = new stripeGC__Stripe_Event__c(
            stripeGC__stripe_event_id__c = 'evt_007',
            stripeGC__request_body__c    = ''
        );

        Assert.isNull(StripePaymentPayload.parse(evt));
    }

    @isTest
    static void items_semicolonSeparatedWithQuantities_parsesCorrectly() {
        stripeGC__Stripe_Event__c evt = paymentEvent(
            'evt_008', 'cus_008', 6000, 'ch_008',
            'x@x.com', 'X Y', 'FOOD:3;MED:1;WATER:2'
        );

        List<StripePaymentPayload.ParsedItem> items = StripePaymentPayload.parse(evt).items();

        Assert.areEqual(3,       items.size());
        Assert.areEqual('FOOD',  items[0].code);
        Assert.areEqual(3,       items[0].quantity);
        Assert.areEqual('MED',   items[1].code);
        Assert.areEqual(1,       items[1].quantity);
        Assert.areEqual('WATER', items[2].code);
        Assert.areEqual(2,       items[2].quantity);
    }

    @isTest
    static void items_codeWithoutQuantity_defaultsToOne() {
        stripeGC__Stripe_Event__c evt = paymentEvent(
            'evt_009', 'cus_009', 1000, 'ch_009', 'x@x.com', 'X Y', 'FOOD'
        );

        List<StripePaymentPayload.ParsedItem> items = StripePaymentPayload.parse(evt).items();

        Assert.areEqual(1,      items.size());
        Assert.areEqual('FOOD', items[0].code);
        Assert.areEqual(1,      items[0].quantity);
    }

    @isTest
    static void items_nullDescription_returnsEmptyList() {
        stripeGC__Stripe_Event__c evt = paymentEvent(
            'evt_010', 'cus_010', 1000, 'ch_010', 'x@x.com', 'X Y', null
        );

        Assert.isTrue(StripePaymentPayload.parse(evt).items().isEmpty());
    }

    @isTest
    static void parse_amountConvertedFromCentsToDecimal() {
        stripeGC__Stripe_Event__c evt = paymentEvent(
            'evt_011', 'cus_011', 12345, 'ch_011', 'x@x.com', 'X Y', null
        );

        StripePaymentPayload p = StripePaymentPayload.parse(evt);

        Assert.areEqual(123.45, p.amount);
    }

    @isTest
    static void parse_unixTimestampConvertedToDate() {
        stripeGC__Stripe_Event__c evt = paymentEvent(
            'evt_012', 'cus_012', 1000, 'ch_012', 'x@x.com', 'X Y', null
        );

        StripePaymentPayload p = StripePaymentPayload.parse(evt);

        Assert.isNotNull(p.transactionDate);
        Assert.areEqual(2024, p.transactionDate.year()); // unix 1716393600 = 2024-05-22
    }

    // ── StripeRefundPayload ──────────────────────────────────────────────────

    @isTest
    static void refundParse_fullPayload_mapsAllFields() {
        stripeGC__Stripe_Event__c evt = refundEvent('evt_r001', 'ch_r001', 2500);

        StripeRefundPayload r = StripeRefundPayload.parse(evt);

        Assert.areEqual('ch_r001', r.chargeId);
        Assert.areEqual(25.00,     r.amount);
        Assert.isNotNull(r.refundDate);
    }

    @isTest
    static void refundParse_blankChargeId_returnsNull() {
        stripeGC__Stripe_Event__c evt = new stripeGC__Stripe_Event__c(
            stripeGC__stripe_event_id__c = 'evt_r002',
            stripeGC__event_name__c      = 'charge.refunded',
            stripeGC__request_body__c    = JSON.serialize(new Map<String, Object>{
                'data' => new Map<String, Object>{
                    'object' => new Map<String, Object>{
                        'id'              => '',
                        'amount_refunded' => 1000,
                        'created'         => 1716393600
                    }
                }
            })
        );

        Assert.isNull(StripeRefundPayload.parse(evt));
    }

    @isTest
    static void refundParse_amountConvertedFromCentsToDecimal() {
        stripeGC__Stripe_Event__c evt = refundEvent('evt_r003', 'ch_r003', 7550);

        StripeRefundPayload r = StripeRefundPayload.parse(evt);

        Assert.areEqual(75.50, r.amount);
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

    private static stripeGC__Stripe_Event__c paymentEventNoBillingName(
        String eventId, String customerId, Integer amountCents,
        String chargeId, String email, String description
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
                        'receipt_email' => null,
                        'charges'       => new Map<String, Object>{
                            'data' => new List<Object>{
                                new Map<String, Object>{
                                    'billing_details' => new Map<String, Object>{
                                        'name'  => null,
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
        String eventId, String customerId, Integer amountCents, String chargeId
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
                        'description'   => null,
                        'created'       => 1716393600,
                        'receipt_email' => null
                    }
                }
            })
        );
    }

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
                        'created'         => 1716393600
                    }
                }
            })
        );
    }
}