public without sharing class StripeRefundService {

    public static void process(List<stripeGC__Stripe_Event__c> events) {
        List<StripeRefundPayload> refunds = parseRefunds(events);
        if (refunds.isEmpty()) return;
        insertGiftRefunds(refunds);
    }

    // ── Parsing ──────────────────────────────────────────────────────────────

    private static List<StripeRefundPayload> parseRefunds(List<stripeGC__Stripe_Event__c> events) {
        List<StripeRefundPayload> refunds = new List<StripeRefundPayload>();
        for (stripeGC__Stripe_Event__c evt : events) {
            try {
                StripeRefundPayload r = StripeRefundPayload.parse(evt);
                if (r != null) refunds.add(r);
            } catch (Exception ex) {
                StripeLogger.error('Failed parsing refund event ' + evt.stripeGC__stripe_event_id__c, ex);
            }
        }
        return refunds;
    }

    // ── GiftRefund Creation ──────────────────────────────────────────────────

    private static void insertGiftRefunds(List<StripeRefundPayload> refunds) {
        Set<String> chargeIds = new Set<String>();
        for (StripeRefundPayload r : refunds) chargeIds.add(r.chargeId);

        Map<String, Id> gtIdByChargeId = new Map<String, Id>();
        for (GiftTransaction gt : StripeSelector.getGiftTransactionsByChargeIds(chargeIds)) {
            gtIdByChargeId.put(gt.Stripe_Charge_Id__c, gt.Id);
        }

        List<GiftRefund> toInsert = new List<GiftRefund>();
        for (StripeRefundPayload r : refunds) {
            Id gtId = gtIdByChargeId.get(r.chargeId);
            if (gtId == null) {
                StripeLogger.error('No GiftTransaction found for charge ' + r.chargeId);
                continue;
            }
            toInsert.add(StripeRecordBuilder.buildGiftRefund(gtId, r));
        }

        Database.SaveResult[] results = Database.insert(toInsert, false);
        for (Database.SaveResult r : results) {
            if (!r.isSuccess() && !r.getErrors().isEmpty()) {
                StripeLogger.error('GiftRefund insert failed: ' + r.getErrors()[0].getMessage());
            }
        }
    }
}