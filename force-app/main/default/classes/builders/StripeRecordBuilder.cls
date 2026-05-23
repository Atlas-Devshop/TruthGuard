public class StripeRecordBuilder {

    public static Account buildPersonAccount(StripePaymentPayload p, Id recordTypeId) {
        Account pa      = new Account();
        pa.RecordTypeId = recordTypeId;
        pa.FirstName    = p.firstName;
        pa.LastName     = String.isNotBlank(p.lastName) ? p.lastName : 'Unknown';
        if (String.isNotBlank(p.email))            pa.PersonEmail              = p.email;
        if (String.isNotBlank(p.stripeCustomerId)) pa.stripeGC__Customer_Id__c = p.stripeCustomerId;
        pa.Source__c = 'Stripe';
        return pa;
    }

    public static GiftTransaction buildGiftTransaction(Id donorId, StripePaymentPayload p) {
        GiftTransaction gt = new GiftTransaction();
        gt.DonorId             = donorId;
        gt.OriginalAmount      = p.amount;
        gt.Fee__c              = p.fee;
        gt.TransactionDueDate  = p.transactionDate;
        gt.TransactionDate     = p.transactionDate;
        gt.Status              = 'Paid';
        gt.PaymentMethod       = 'Stripe';
        gt.Stripe_Event_Id__c  = p.eventId;
        gt.Stripe_Charge_Id__c = p.chargeId;
        gt.Name                = transactionName(p.lastName, p.transactionDate);
        return gt;
    }

    public static Gift_Transaction_Line__c buildTransactionLine(
        Id gtId,
        StripePaymentPayload.ParsedItem item,
        Decimal unitPrice,
        Id productId
    ) {
        Gift_Transaction_Line__c line = new Gift_Transaction_Line__c();
        line.Gift_Transaction__c = gtId;
        line.Product__c          = productId;
        line.Quantity__c         = item.quantity;
        line.Unit_Price__c       = unitPrice;
        return line;
    }

    public static Product2 buildProduct(String sku) {
        return new Product2(Name = sku, StockKeepingUnit = sku, IsActive = true);
    }

    public static GiftRefund buildGiftRefund(Id gtId, StripeRefundPayload r) {
        GiftRefund refund        = new GiftRefund();
        refund.GiftTransactionId = gtId;
        refund.Status            = 'Completed';
        refund.Amount            = r.amount;
        refund.Date              = r.refundDate;
        return refund;
    }

    // ── Private Helpers ──────────────────────────────────────────────────────

    private static String transactionName(String lastName, Date txnDate) {
        return (String.isNotBlank(lastName) ? lastName : 'Donor')
            + '-' + txnDate.month() + '/' + txnDate.day() + '/' + txnDate.year();
    }
}