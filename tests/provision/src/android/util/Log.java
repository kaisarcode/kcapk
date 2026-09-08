package android.util;

public final class Log {
    public static int i(String tag, String msg) {
        System.err.println("I/" + tag + ": " + msg);
        return 0;
    }

    public static int w(String tag, String msg) {
        System.err.println("W/" + tag + ": " + msg);
        return 0;
    }

    public static int w(String tag, String msg, Throwable tr) {
        System.err.println("W/" + tag + ": " + msg);
        tr.printStackTrace(System.err);
        return 0;
    }

    public static int e(String tag, String msg) {
        System.err.println("E/" + tag + ": " + msg);
        return 0;
    }

    public static int e(String tag, String msg, Throwable tr) {
        System.err.println("E/" + tag + ": " + msg);
        tr.printStackTrace(System.err);
        return 0;
    }

    private Log() {}
}