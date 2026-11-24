# GraphHopper with the OHM date plugin from src/
FROM maven:3.9-eclipse-temurin-21-noble AS build
ARG GRAPHHOPPER_VERSION=11.1
RUN git clone --quiet --depth 1 --branch ${GRAPHHOPPER_VERSION} https://github.com/graphhopper/graphhopper.git /gh
# The date conversion must match the tiler, so fail the build if the test fails
COPY src/ /build/src/
COPY test/ /build/test/
RUN javac -d /build/test-out /build/src/org/openhistoricalmap/routing/OhmDate.java /build/test/OhmDateTest.java \
 && java -cp /build/test-out OhmDateTest \
 && mkdir -p /gh/web-bundle/src/main/java/org/openhistoricalmap \
 && cp -r /build/src/org/openhistoricalmap/routing /gh/web-bundle/src/main/java/org/openhistoricalmap/
WORKDIR /gh
# Register the OHM encoded values. There is no config hook for this, so patch the
# one place where the server creates GraphHopper, and fail if the patch did nothing.
RUN F=web-bundle/src/main/java/com/graphhopper/http/GraphHopperManaged.java \
 && sed -i 's|^        graphHopper.init(configuration);|        graphHopper.setImportRegistry(new org.openhistoricalmap.routing.OhmImportRegistry());\n        graphHopper.init(configuration);|' $F \
 && grep -q OhmImportRegistry $F
RUN mvn -q -B -DskipTests -pl web -am package \
 && cp "$(ls web/target/graphhopper-web-*.jar | grep -v -e sources -e javadoc | head -1)" /graphhopper.jar
# A graph only loads with the same profiles and encoded values it was built with,
# so tag graphs with a hash of everything that changes them
COPY config/ /build/config/
RUN cat /build/config/* web-bundle/src/main/java/org/openhistoricalmap/routing/*.java \
    | { cat; echo "${GRAPHHOPPER_VERSION}"; } | sha256sum | cut -c1-12 > /graph-version

# noble = Ubuntu 24.04 (Python 3.12), which has osmium wheels
FROM eclipse-temurin:21-jre-noble
RUN apt-get update \
 && apt-get install -y --no-install-recommends curl python3 python3-venv libexpat1 \
 && rm -rf /var/lib/apt/lists/* \
 && python3 -m venv /opt/venv \
 && /opt/venv/bin/pip install --no-cache-dir osmium==4.0.2
ENV PATH=/opt/venv/bin:$PATH \
    DATA_DIR=/data \
    JAVA_OPTS="-Xmx4g"
WORKDIR /app
COPY --from=build /graphhopper.jar /app/graphhopper.jar
COPY --from=build /graph-version /app/graph-version
COPY config/ /app/config/
COPY scripts/ /app/scripts/
COPY web/ /app/web/
RUN chmod +x /app/scripts/*.sh
EXPOSE 8989
CMD ["/app/scripts/start.sh"]
