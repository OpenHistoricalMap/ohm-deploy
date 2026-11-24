package org.openhistoricalmap.routing;

import com.graphhopper.routing.ev.DefaultImportRegistry;
import com.graphhopper.routing.ev.ImportUnit;

/**
 * Adds the ohm_start/ohm_end encoded values. Enable them with
 * graph.encoded_values: ..., ohm_start, ohm_end
 */
public class OhmImportRegistry extends DefaultImportRegistry {
    @Override
    public ImportUnit createImportUnit(String name) {
        if (OhmDateParser.START_KEY.equals(name))
            return ImportUnit.create(name, props -> OhmDateParser.createStart(),
                    (lookup, props) -> new OhmDateParser(
                            lookup.getDecimalEncodedValue(OhmDateParser.START_KEY),
                            lookup.getDecimalEncodedValue(OhmDateParser.END_KEY)),
                    OhmDateParser.END_KEY);
        if (OhmDateParser.END_KEY.equals(name))
            return ImportUnit.create(name, props -> OhmDateParser.createEnd(), null);
        return super.createImportUnit(name);
    }
}
