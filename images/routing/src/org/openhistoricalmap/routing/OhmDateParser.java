package org.openhistoricalmap.routing;

import com.graphhopper.reader.ReaderWay;
import com.graphhopper.routing.ev.DecimalEncodedValue;
import com.graphhopper.routing.ev.DecimalEncodedValueImpl;
import com.graphhopper.routing.ev.EdgeIntAccess;
import com.graphhopper.routing.util.parsers.TagParser;
import com.graphhopper.storage.IntsRef;

/**
 * Stores the validity interval of each way as two decimal years. A missing or
 * malformed start_date means "since always", a missing or malformed end_date
 * means "still exists", so undated ways are routable at any date.
 */
public class OhmDateParser implements TagParser {
    public static final String START_KEY = "ohm_start";
    public static final String END_KEY = "ohm_end";

    // 1/256 year (~1.4 days) is exact in binary, so minStorableValue passes the
    // factor check. 21 bits cover -6000 .. ~2190; the max value means infinity and
    // larger finite values are clamped by setDecimal.
    private static final int BITS = 21;
    private static final double MIN_YEAR = -6000;
    private static final double FACTOR = 1.0 / 256;

    private final DecimalEncodedValue startEnc;
    private final DecimalEncodedValue endEnc;

    public OhmDateParser(DecimalEncodedValue startEnc, DecimalEncodedValue endEnc) {
        this.startEnc = startEnc;
        this.endEnc = endEnc;
    }

    public static DecimalEncodedValue createStart() {
        return new DecimalEncodedValueImpl(START_KEY, BITS, MIN_YEAR, FACTOR, false, false, true);
    }

    public static DecimalEncodedValue createEnd() {
        return new DecimalEncodedValueImpl(END_KEY, BITS, MIN_YEAR, FACTOR, false, false, true);
    }

    @Override
    public void handleWayTags(int edgeId, EdgeIntAccess edgeIntAccess, ReaderWay way, IntsRef relationFlags) {
        double start = OhmDate.toDecimal(way.getTag("start_date", null), false);
        double end = OhmDate.toDecimal(way.getTag("end_date", null), true);

        startEnc.setDecimal(false, edgeId, edgeIntAccess, Double.isNaN(start) ? MIN_YEAR : Math.max(MIN_YEAR, start));
        endEnc.setDecimal(false, edgeId, edgeIntAccess, Double.isNaN(end) ? Double.POSITIVE_INFINITY : Math.max(MIN_YEAR, end));
    }
}
