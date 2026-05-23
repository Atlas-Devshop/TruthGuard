/**
 * StripePaymentPayload
 * --------------------
 * Represents a single payment_intent.succeeded event as a typed Apex object.
 *
 * Responsibilities (all in one place):
 *   - Typed fields for every value the payment flow needs
 *   - parse() factory that builds an instance from a raw Stripe Event record
 *   - Private helpers: JSON traversal, name derivation, amount/date conversion,
 *     description parsing
 */
public class StripePaymentPayload {

    public String  eventId;
    public Decimal amount;
    public Decimal fee;
    public String  description;
    public String  chargeId;
    public String  stripeCustomerId;
    public String  email;
    public String  firstName;
    public String  lastName;
    public Date    transactionDate;

    public List<ParsedItem> items() {
        return parseDescription(this.description);
    }

    // ── Factory ──────────────────────────────────────────────────────────────

    public static StripePaymentPayload parse(stripeGC__Stripe_Event__c evt) {
        if (String.isBlank(evt.stripeGC__request_body__c)) return null;

        Map<String, Object> obj = payloadObject(evt.stripeGC__request_body__c);
        Map<String, Object> bd  = billingDetailsFromCharges(obj);

        StripePaymentPayload p = new StripePaymentPayload();
        p.eventId          = evt.stripeGC__stripe_event_id__c;
        p.amount           = toDecimalCents(obj.get('amount'));
        p.chargeId         = (String) obj.get('latest_charge');
        p.stripeCustomerId = (String) obj.get('customer');
        p.description      = (String) obj.get('description');
        p.transactionDate  = parseUnixDate(obj.get('created'));
        p.fee              = 0;
        p.email            = emailFrom(obj, bd);

        applyName(p, bd != null ? (String) bd.get('name') : null);

        return p;
    }

    // ── Private Helpers ──────────────────────────────────────────────────────

    private static Map<String, Object> payloadObject(String requestBody) {
        Map<String, Object> body = (Map<String, Object>) JSON.deserializeUntyped(requestBody);
        Map<String, Object> data = (Map<String, Object>) body.get('data');
        return (Map<String, Object>) data.get('object');
    }

    private static Map<String, Object> billingDetailsFromCharges(Map<String, Object> obj) {
        try {
            List<Object> charges = (List<Object>) ((Map<String, Object>) obj.get('charges')).get('data');
            if (charges == null || charges.isEmpty()) return null;
            return (Map<String, Object>) ((Map<String, Object>) charges[0]).get('billing_details');
        } catch (Exception ignored) { return null; }
    }

    private static String emailFrom(Map<String, Object> obj, Map<String, Object> billingDetails) {
        String email = (String) obj.get('receipt_email');
        if (String.isNotBlank(email)) return email;
        return billingDetails != null ? (String) billingDetails.get('email') : null;
    }

    private static void applyName(StripePaymentPayload p, String fullName) {
        if (String.isNotBlank(fullName)) {
            List<String> words = fullName.trim().split('\\s+');
            p.lastName = words[words.size() - 1];
            if (words.size() > 1) {
                String first = words[0];
                for (Integer i = 1; i < words.size() - 1; i++) first += ' ' + words[i];
                p.firstName = first;
            }
            return;
        }
        if (String.isNotBlank(p.email)) {
            String local = p.email.split('@')[0].replaceAll('[^a-zA-Z]', '');
            p.lastName = String.isNotBlank(local)
                ? local.substring(0, 1).toUpperCase() + local.substring(1).toLowerCase()
                : 'Unknown';
            return;
        }
        p.lastName = 'Unknown';
    }

    private static Decimal toDecimalCents(Object raw) {
        if (raw == null) return 0;
        Decimal cents;
        if      (raw instanceof Integer) cents = Decimal.valueOf((Integer) raw);
        else if (raw instanceof Long)    cents = (Decimal) raw;
        else if (raw instanceof Decimal) cents = (Decimal) raw;
        else                             cents = Decimal.valueOf(String.valueOf(raw));
        return cents / 100.0;
    }

    private static Date parseUnixDate(Object raw) {
        if (raw == null) return Date.today();
        Long unixSec;
        if      (raw instanceof Long)    unixSec = (Long) raw;
        else if (raw instanceof Integer) unixSec = (Long)((Integer) raw);
        else                             unixSec = Long.valueOf(String.valueOf(raw));
        return DateTime.newInstance(unixSec * 1000L).dateGmt();
    }

    private static List<ParsedItem> parseDescription(String description) {
        List<ParsedItem> items = new List<ParsedItem>();
        if (String.isBlank(description)) return items;

        for (String seg : description.split(';')) {
            seg = seg.trim();
            if (String.isBlank(seg)) continue;
            ParsedItem it = new ParsedItem();
            if (seg.contains(':')) {
                List<String> parts = seg.split(':');
                it.code = parts[0].trim();
                try { it.quantity = Integer.valueOf(parts[parts.size() - 1].trim()); }
                catch (Exception e) { it.quantity = 1; }
            } else {
                it.code     = seg;
                it.quantity = 1;
            }
            items.add(it);
        }
        return items;
    }

    // ── Inner Class ──────────────────────────────────────────────────────────

    public class ParsedItem {
        public String  code;
        public Integer quantity;
    }
}