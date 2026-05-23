public without sharing class StripePaymentService {

    public static void process(List<stripeGC__Stripe_Event__c> events) {
        List<StripePaymentPayload> payments = parseNewPayments(events);
        if (payments.isEmpty()) return;

        Map<String, Id> donorByEventId = resolveOrCreateDonors(payments);
        Map<String, Id> productBySku   = resolveOrCreateProducts(payments);

        insertTransactionsAndLines(payments, donorByEventId, productBySku);
    }

    // ── Parsing ──────────────────────────────────────────────────────────────

    private static List<StripePaymentPayload> parseNewPayments(List<stripeGC__Stripe_Event__c> events) {
        Set<String> processed = StripeSelector.getProcessedEventIds(collectEventIds(events));
        List<StripePaymentPayload> payments = new List<StripePaymentPayload>();

        for (stripeGC__Stripe_Event__c evt : events) {
            if (processed.contains(evt.stripeGC__stripe_event_id__c)) continue;
            try {
                StripePaymentPayload p = StripePaymentPayload.parse(evt);
                if (p != null) payments.add(p);
            } catch (Exception ex) {
                StripeLogger.error('Failed parsing payment event ' + evt.stripeGC__stripe_event_id__c, ex);
            }
        }
        return payments;
    }

    // ── Donor Resolution ─────────────────────────────────────────────────────

    private static Map<String, Id> resolveOrCreateDonors(List<StripePaymentPayload> payments) {
        Map<String, Id> byCustomerId = new Map<String, Id>();
        Map<String, Id> byEmail      = new Map<String, Id>();

        for (Account a : StripeSelector.getPersonAccounts(collectCustomerIds(payments), collectEmails(payments))) {
            if (String.isNotBlank(a.stripeGC__Customer_Id__c)) byCustomerId.put(a.stripeGC__Customer_Id__c, a.Id);
            if (String.isNotBlank(a.PersonEmail))              byEmail.put(a.PersonEmail.toLowerCase(), a.Id);
        }

        Map<String, Id>                        donorByEventId    = new Map<String, Id>();
        Map<Id, String>                        emailMatchUpdates = new Map<Id, String>();
        Map<String, List<StripePaymentPayload>> orphansByKey     = new Map<String, List<StripePaymentPayload>>();

        for (StripePaymentPayload p : payments) {
            Id donorId = byCustomerId.get(p.stripeCustomerId);
            if (donorId != null) {
                donorByEventId.put(p.eventId, donorId);
                continue;
            }

            donorId = byEmail.get(normalizeEmail(p.email));
            if (donorId != null) {
                donorByEventId.put(p.eventId, donorId);
                if (String.isNotBlank(p.stripeCustomerId)) emailMatchUpdates.put(donorId, p.stripeCustomerId);
                continue;
            }

            String orphanKey = String.isNotBlank(p.email) ? normalizeEmail(p.email) : p.stripeCustomerId;
            if (String.isBlank(orphanKey)) {
                StripeLogger.error('Cannot identify donor for event ' + p.eventId + ': no email or customer ID');
                continue;
            }
            if (!orphansByKey.containsKey(orphanKey)) orphansByKey.put(orphanKey, new List<StripePaymentPayload>());
            orphansByKey.get(orphanKey).add(p);
        }

        if (!orphansByKey.isEmpty())      donorByEventId.putAll(createPersonAccounts(orphansByKey));
        if (!emailMatchUpdates.isEmpty()) backfillStripeCustomerIds(emailMatchUpdates);

        return donorByEventId;
    }

    private static Map<String, Id> createPersonAccounts(Map<String, List<StripePaymentPayload>> orphansByKey) {
        Id             paRecordTypeId = StripeSelector.getPersonAccountRecordTypeId();
        List<Account>  toInsert       = new List<Account>();
        List<String>   keys           = new List<String>();

        for (String key : orphansByKey.keySet()) {
            toInsert.add(StripeRecordBuilder.buildPersonAccount(orphansByKey.get(key)[0], paRecordTypeId));
            keys.add(key);
        }

        Map<String, Id>       donorByEventId = new Map<String, Id>();
        Database.SaveResult[] results        = Database.insert(toInsert, false);

        for (Integer i = 0; i < results.size(); i++) {
            String key = keys[i];
            if (results[i].isSuccess()) {
                Id newId = results[i].getId();
                for (StripePaymentPayload p : orphansByKey.get(key)) donorByEventId.put(p.eventId, newId);
            } else {
                String err = results[i].getErrors()[0].getMessage();
                for (StripePaymentPayload p : orphansByKey.get(key)) {
                    StripeLogger.error('Failed creating PersonAccount for event ' + p.eventId + ': ' + err);
                }
            }
        }
        return donorByEventId;
    }

    private static void backfillStripeCustomerIds(Map<Id, String> updates) {
        List<Account> toUpdate = new List<Account>();
        for (Id accId : updates.keySet()) {
            toUpdate.add(new Account(Id = accId, stripeGC__Customer_Id__c = updates.get(accId)));
        }
        Database.update(toUpdate, false);
    }

    // ── Product Resolution ───────────────────────────────────────────────────

    private static Map<String, Id> resolveOrCreateProducts(List<StripePaymentPayload> payments) {
        Set<String> allCodes = new Set<String>();
        for (StripePaymentPayload p : payments) {
            for (StripePaymentPayload.ParsedItem it : p.items()) allCodes.add(it.code);
        }
        if (allCodes.isEmpty()) return new Map<String, Id>();

        Map<String, Id> bySku = new Map<String, Id>();
        for (Product2 prod : StripeSelector.getActiveProductsBySkus(allCodes)) {
            bySku.put(prod.StockKeepingUnit, prod.Id);
        }

        Set<String> missing = new Set<String>();
        for (String code : allCodes) {
            if (!bySku.containsKey(code)) missing.add(code);
        }
        if (!missing.isEmpty()) bySku.putAll(createProducts(missing));

        return bySku;
    }

    private static Map<String, Id> createProducts(Set<String> codes) {
        List<Product2> toInsert = new List<Product2>();
        List<String>   skus     = new List<String>();

        for (String code : codes) {
            toInsert.add(StripeRecordBuilder.buildProduct(code));
            skus.add(code);
        }

        Map<String, Id>       result  = new Map<String, Id>();
        Database.SaveResult[] results = Database.insert(toInsert, false);

        for (Integer i = 0; i < results.size(); i++) {
            if (results[i].isSuccess()) {
                result.put(skus[i], results[i].getId());
            } else {
                StripeLogger.error('Failed creating Product2 for SKU "' + skus[i] + '": ' + results[i].getErrors()[0].getMessage());
            }
        }
        return result;
    }

    // ── Transactions & Lines ─────────────────────────────────────────────────

    private static void insertTransactionsAndLines(
        List<StripePaymentPayload> payments,
        Map<String, Id>            donorByEventId,
        Map<String, Id>            productBySku
    ) {
        List<GiftTransaction>      toInsert = new List<GiftTransaction>();
        List<StripePaymentPayload> bound    = new List<StripePaymentPayload>();

        for (StripePaymentPayload p : payments) {
            Id donorId = donorByEventId.get(p.eventId);
            if (donorId == null) continue;
            toInsert.add(StripeRecordBuilder.buildGiftTransaction(donorId, p));
            bound.add(p);
        }
        if (toInsert.isEmpty()) return;

        Database.SaveResult[]          results = Database.insert(toInsert, false);
        List<Gift_Transaction_Line__c> lines   = new List<Gift_Transaction_Line__c>();

        for (Integer i = 0; i < results.size(); i++) {
            if (!results[i].isSuccess()) {
                StripeLogger.error('GiftTransaction insert failed for event ' + bound[i].eventId + ': ' + results[i].getErrors()[0].getMessage());
                continue;
            }
            lines.addAll(buildTransactionLines(results[i].getId(), bound[i], productBySku));
        }

        if (lines.isEmpty()) return;

        Database.SaveResult[] lineResults = Database.insert(lines, false);
        for (Database.SaveResult r : lineResults) {
            if (!r.isSuccess() && !r.getErrors().isEmpty()) {
                StripeLogger.error('GiftTransactionLine insert failed: ' + r.getErrors()[0].getMessage());
            }
        }
    }

    private static List<Gift_Transaction_Line__c> buildTransactionLines(Id gtId, StripePaymentPayload p, Map<String, Id> productBySku) {
        List<StripePaymentPayload.ParsedItem> items = p.items();
        List<Gift_Transaction_Line__c>        lines = new List<Gift_Transaction_Line__c>();
        if (items.isEmpty()) return lines;

        Integer totalQty  = 0;
        for (StripePaymentPayload.ParsedItem it : items) totalQty += it.quantity;
        Decimal unitPrice = totalQty > 0 ? (p.amount / totalQty).setScale(2) : 0;

        for (StripePaymentPayload.ParsedItem it : items) {
            Id productId = productBySku.get(it.code);
            if (productId == null) {
                StripeLogger.error('Product not resolved for SKU "' + it.code + '" on event ' + p.eventId);
                continue;
            }
            lines.add(StripeRecordBuilder.buildTransactionLine(gtId, it, unitPrice, productId));
        }
        return lines;
    }

    // ── Utilities ────────────────────────────────────────────────────────────

    private static Set<String> collectEventIds(List<stripeGC__Stripe_Event__c> events) {
        Set<String> ids = new Set<String>();
        for (stripeGC__Stripe_Event__c e : events) {
            if (String.isNotBlank(e.stripeGC__stripe_event_id__c)) ids.add(e.stripeGC__stripe_event_id__c);
        }
        return ids;
    }

    private static Set<String> collectCustomerIds(List<StripePaymentPayload> payments) {
        Set<String> ids = new Set<String>();
        for (StripePaymentPayload p : payments) if (String.isNotBlank(p.stripeCustomerId)) ids.add(p.stripeCustomerId);
        return ids;
    }

    private static Set<String> collectEmails(List<StripePaymentPayload> payments) {
        Set<String> emails = new Set<String>();
        for (StripePaymentPayload p : payments) if (String.isNotBlank(p.email)) emails.add(normalizeEmail(p.email));
        return emails;
    }

    private static String normalizeEmail(String email) {
        return String.isNotBlank(email) ? email.toLowerCase() : null;
    }
}