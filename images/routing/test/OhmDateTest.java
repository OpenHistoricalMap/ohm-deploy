import org.openhistoricalmap.routing.OhmDate;

/**
 * Checks OhmDate against the tiler conversion
 * (pad_date + isodatetodecimaldate in OpenHistoricalMap/DateFunctions-plpgsql).
 */
public class OhmDateTest {
    private static int failures = 0;

    public static void main(String[] args) {
        check("1925", false, 1925.00137);
        check("1925", true, 1925.99863);
        check("1925-03", false, 1925.16301);
        check("1925-03", true, 1925.24521);
        check("1925-03-12", false, 1925.19315);
        check("2000-02-29", false, 2000.16257);
        check("-0500", false, -499.99863);
        check("-0500", true, -499.00137);
        check("0000", false, 0.00137);
        check("-0001-12-31", false, -0.00137);
        check("+1925", false, 1925.00137);
        check("1900-02-29", false, Double.NaN);
        check("1925-13", false, Double.NaN);
        check("~1900", false, Double.NaN);
        check("1900s", false, Double.NaN);
        check(null, false, Double.NaN);
        if (failures > 0) {
            System.out.println(failures + " failed");
            System.exit(1);
        }
        System.out.println("all passed");
    }

    private static void check(String value, boolean end, double expected) {
        double actual = OhmDate.toDecimal(value, end);
        boolean ok = Double.isNaN(expected) ? Double.isNaN(actual) : Math.abs(actual - expected) < 1e-9;
        if (!ok) {
            failures++;
            System.out.println("FAIL " + value + " end=" + end + ": expected " + expected + ", got " + actual);
        }
    }
}
