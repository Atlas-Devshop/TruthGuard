public class StripeLogger {

    public static void error(String message) {
        try {
            Logger.error(message);
            Logger.saveLog();
        } catch (Exception ignored) {
            System.debug(LoggingLevel.ERROR, message);
        }
    }

    public static void error(String message, Exception ex) {
        try {
            Logger.error(message, ex);
            Logger.saveLog();
        } catch (Exception ignored) {
            System.debug(LoggingLevel.ERROR, message + ' | ' + ex.getMessage());
        }
    }
}