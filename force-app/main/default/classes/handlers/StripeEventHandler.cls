public with sharing class StripeEventHandler {

    private static final String EVT_PAYMENT_SUCCEEDED = 'payment_intent.succeeded';
    private static final String EVT_CHARGE_REFUNDED   = 'charge.refunded';

    public static void handleNewEvents(List<stripeGC__Stripe_Event__c> events) {
        List<stripeGC__Stripe_Event__c> paymentEvents = eventsOfType(events, EVT_PAYMENT_SUCCEEDED);
        List<stripeGC__Stripe_Event__c> refundEvents  = eventsOfType(events, EVT_CHARGE_REFUNDED);

        if (!paymentEvents.isEmpty()) StripePaymentService.process(paymentEvents);
        if (!refundEvents.isEmpty())  StripeRefundService.process(refundEvents);
    }

    private static List<stripeGC__Stripe_Event__c> eventsOfType(List<stripeGC__Stripe_Event__c> events, String type) {
        List<stripeGC__Stripe_Event__c> result = new List<stripeGC__Stripe_Event__c>();
        for (stripeGC__Stripe_Event__c e : events) {
            if (e.stripeGC__event_name__c == type) result.add(e);
        }
        return result;
    }
}