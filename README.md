# quarkus-performer

This project is a proof of concept to "port" over our Java FIT Performer to use the Couchbase Quarkus extension.
It starts a gRPC server which executes FIT Driver (gRPC client) requests against a Couchbase server.

## Updating the performer
Most of the code under `src/main` is a copy of the Java FIT performer and its protocol from
[couchbase-jvm-clients](https://github.com/couchbase/couchbase-jvm-clients). `updatePerformer.sh` regenerates
that copy for the Java SDK version that a quarkus-couchbase checkout ships, then applies the Quarkus changes:

```shell script
QUARKUS_COUCHBASE_DIR=../quarkus-couchbase ./updatePerformer.sh
```

Only `QuarkusPerformer.java`, `ReflectionProcessing.java` and the files in `quarkus-overrides/` belong to this
project. The script replaces everything else, and it fails if a Quarkus change no longer applies.

## Prebuilt images
The `Publish FIT performer images` workflow builds the performer against a quarkus-couchbase tag, branch or PR ref,
checks that it starts and answers `performerCapsFetch`, and publishes two images:
- `ghcr.io/couchbaselabs/quarkus-fit-performer:<tag>`, JVM mode
- `ghcr.io/couchbaselabs/quarkus-native-fit-performer:<tag>`, native mode

Run it from the Actions tab. It only runs manually for now.

## Running the tests
You'll need:
- quarkus-performer (FIT Performer, a gRPC Server)
- transaction-fit-performer (FIT Driver, a gRPC Client)
- Couchbase Server (Local or Capella)
- Mandrel 24.0.2.r22 or Graal 22.0.2 (or latest for both)

> Using [SDKMAN!](https://sdkman.io/) is recommended to install and manage different JDKs.

### Step 1
Start a Couchbase Server

With Docker:
```shell script
docker run -d --name couchbase -p 8091-8097:8091-8097 -p 11210:11210 couchbase:latest
```
Head to https://localhost:8091 to finish setting up your cluster.

### Step 2
Clone this repository and `cd` into it:
```shell script
git clone git@github.com:couchbaselabs/quarkus-performer.git
cd quarkus-performer
```
To install/use Mandrel, do:
```shell script
sdk install java 25.0.1.r25-mandrel
sdk use java 25.0.1.r25-mandrel
```
> Note that `sdk use java {version}` will use that version in your current shell. Opening a new terminal session will use the default Java version, which you can specify with `sdk default java {version}`.

Open `application.properties` in `quarkus-performer/src/main/resources` and modify the credentials to the ones you chose when setting up your Cluster (or change the connection string if your Cluster is remote).

> Cluster configurations in `application.properties` are set at build-time and cannot be modified at run-time. Changing them will require re-compiling.

Still with `quarkus-performer` open in a terminal, run:
```shell script
mvn clean install -Dnative -DskipTests
```
Once it is compiled, run the performer runner located in `/target`.

```shell script
./target/quarkus-performer-1.0.0-SNAPSHOT-runner
```

### Step 3
Clone transactions-fit-performer:
```shell script
git clone git@github.com:couchbaselabs/transactions-fit-performer.git
```
Open the project in another IDE window and follow the README.md to configure FITConfiguration.json.

Right click and run any test in `test-driver/src/test/java/com/couchbase`.

# Other Infos

## Packaging and running the application

The application can be packaged using:
```shell script
./mvnw package
```
It produces the `quarkus-run.jar` file in the `target/quarkus-app/` directory.
Be aware that it’s not an _über-jar_ as the dependencies are copied into the `target/quarkus-app/lib/` directory.

The application is now runnable using `java -jar target/quarkus-app/quarkus-run.jar`.

If you want to build an _über-jar_, execute the following command:
```shell script
./mvnw package -Dquarkus.package.jar.type=uber-jar
```

The application, packaged as an _über-jar_, is now runnable using `java -jar target/*-runner.jar`.

## Creating a native executable

You can create a native executable using:
```shell script
./mvnw package -Dnative
```

Or, if you don't have GraalVM installed, you can run the native executable build in a container using:
```shell script
./mvnw package -Dnative -Dquarkus.native.container-build=true
```

You can then execute your native executable with: `./target/quarkus-couchbase-demo-1.0.0-SNAPSHOT-runner`

If you want to learn more about building native executables, please consult https://quarkus.io/guides/maven-tooling.