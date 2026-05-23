/**
 * StripeRefundPayload
 * -------------------
 * Represents a single charge.refunded event as a typed Apex object.
 *
 * Responsibilities (all in one place):
 *   - Typed fields for every value the refund flow needs
 *   - parse() factory that builds an instance from a raw Stripe Event record
 *   - Private helpers: JSON traversal, amount/date conversion
 */
public class StripeRefundPayload {

    public String  chargeId;
    public Decimal amount;
    public Date    refundDate;

    // ── Factory ──────────────────────────────────────────────────────────────

    public static StripeRefundPayload parse(stripeGC__Stripe_Event__c evt) {
        Map<String, Object> body = (Map<String, Object>) JSON.deserializeUntyped(evt.stripeGC__request_body__c);
        Map<String, Object> data = (Map<String, Object>) body.get('data');
        Map<String, Object> obj  = (Map<String, Object>) data.get('object');

        String chargeId = (String) obj.get('id');
        if (String.isBlank(chargeId)) return null;

        StripeRefundPayload r = new StripeRefundPayload();
        r.chargeId   = chargeId;
        r.amount     = toDecimalCents(obj.get('amount_refunded'));
        r.refundDate = parseUnixDate(obj.get('created'));
        return r;
    }

    // ── Private Helpers ──────────────────────────────────────────────────────

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
}