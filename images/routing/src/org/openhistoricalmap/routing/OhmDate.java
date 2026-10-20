package org.openhistoricalmap.routing;

import java.util.regex.Matcher;
import java.util.regex.Pattern;

/**
 * Converts OHM start_date/end_date values to decimal years, using the same rules as
 * the tiler (pad_date + isodatetodecimaldate from OpenHistoricalMap/DateFunctions-plpgsql):
 * truncated dates are padded to the first (start) or last (end) day, the day is taken
 * at noon, and ISO year 0 is 1 BCE.
 */
public final class OhmDate {
    private static final Pattern DATE = Pattern.compile("^\\+?(-?\\d+)(?:-(\\d\\d))?(?:-(\\d\\d))?$");

    private OhmDate() {
    }

    /** Returns the decimal year, or NaN when the value is missing or malformed. */
    public static double toDecimal(String value, boolean end) {
        if (value == null)
            return Double.NaN;
        Matcher m = DATE.matcher(value.trim());
        if (!m.matches() || (m.group(2) == null && m.group(3) != null))
            return Double.NaN;
        int year;
        try {
            year = Integer.parseInt(m.group(1));
        } catch (NumberFormatException e) {
            return Double.NaN;
        }
        int month = m.group(2) != null ? Integer.parseInt(m.group(2)) : (end ? 12 : 1);
        if (month < 1 || month > 12)
            return Double.NaN;
        int day = m.group(3) != null ? Integer.parseInt(m.group(3)) : (end ? daysInMonth(year, month) : 1);
        if (day < 1 || day > daysInMonth(year, month))
            return Double.NaN;

        if (year <= 0)
            year -= 1;
        double dayNumber = yday(year, month, day) - 0.5;
        double fraction = dayNumber / (isLeap(year) ? 366 : 365);
        double decimal = year < 0 ? 2 + year - (1 - fraction) : year + fraction;
        return Math.round(decimal * 1e5) / 1e5;
    }

    static boolean isLeap(int year) {
        if (year <= 0)
            year += 1;
        return year % 4 == 0 && (year % 100 != 0 || year % 400 == 0);
    }

    static int daysInMonth(int year, int month) {
        switch (month) {
            case 2:
                return isLeap(year) ? 29 : 28;
            case 4:
            case 6:
            case 9:
            case 11:
                return 30;
            default:
                return 31;
        }
    }

    static int yday(int year, int month, int day) {
        int days = 0;
        for (int m = 1; m < month; m++)
            days += daysInMonth(year, m);
        return days + day;
    }
}
