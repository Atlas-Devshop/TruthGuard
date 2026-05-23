/**
 * StripeEventTrigger
 * ------------------
 * Fires after insert of stripeGC__Stripe_Event__c records.
 * Delegates processing to StripeEventHandler.
 *
 * Author: Atlas Devshop
 */
trigger StripeEventTrigger on stripeGC__Stripe_Event__c (after insert) {
    StripeEventHandler.handleNewEvents(Trigger.new);
}