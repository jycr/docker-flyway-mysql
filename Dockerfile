FROM maven:3-jdk-11-slim AS build-env

# see: https://stackoverflow.com/questions/47969389/how-can-i-cache-maven-dependencies-and-plugins-in-a-docker-multi-stage-build-lay#answer-47970045
RUN mkdir -p /opt/workspace
WORKDIR /opt/workspace

ARG JAVA_TOOL_OPTIONS
COPY .mvn ./.mvn
# initialize cache for "root dependencies"
RUN mvn -B -s /usr/share/maven/ref/settings-docker.xml help:evaluate -Dexpression=settings.localRepository

COPY pom.yml .
# initialize cache for "project dependencies"
RUN mvn -B -s /usr/share/maven/ref/settings-docker.xml dependency:go-offline -f ./pom.yml

COPY ./src/ ./src/
RUN mvn -B -s /usr/share/maven/ref/settings-docker.xml clean package

COPY ./build-jre.sh .
# Build java runtime
RUN ./build-jre.sh

RUN mkdir -p /app/jars

#FROM gcr.io/distroless/java
#FROM openjdk:11-slim
FROM gcr.io/distroless/base
COPY --from=build-env /opt/workspace/target/dependency/flyway-* /app/
COPY --from=build-env /opt/workspace/target/java-runtime /java-runtime
COPY --from=build-env /app/jars /app/jars

# Note: neither gcr.io/distroless/base nor the jlink build do include libz.so needed by the java executable, thus we copy it from the system
# See: https://github.com/GoogleContainerTools/distroless/issues/217
COPY --from=build-env /lib/x86_64-linux-gnu/libz.so.1 /lib/x86_64-linux-gnu/libz.so.1
COPY --from=build-env /lib/x86_64-linux-gnu/libgcc_s.so.1 /lib/x86_64-linux-gnu/libgcc_s.so.1
COPY --from=build-env /usr/lib/x86_64-linux-gnu/libstdc++.so.6 /usr/lib/x86_64-linux-gnu/libstdc++.so.6

WORKDIR /app

ENTRYPOINT ["/java-runtime/bin/java","-Djava.security.egd=file:/dev/urandom","-cp","/app/lib/community/*:/app/lib/drivers/*","org.flywaydb.commandline.Main"]
CMD ["-?"]
