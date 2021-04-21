# lucene-analyzers-kuromoji-neologd
[![Build Status](https://travis-ci.org/myui/lucene-analyzers-kuromoji-neologd.svg?branch=master)](https://travis-ci.org/myui/lucene-analyzers-kuromoji-neologd) 
[![Maven Central](https://maven-badges.herokuapp.com/maven-central/io.github.myui/lucene-analyzers-kuromoji-neologd/badge.svg)](https://search.maven.org/#search%7Cga%7C1%7Cg%3A%22io.github.myui%22%20a%3Alucene-analyzers-kuromoji-neologd) 
[![License](http://img.shields.io/:license-Apache_v2-blue.svg)](https://github.com/myui/lucene-analyzers-kuromoji-neologd/blob/master/LICENSE)

Repository to build lucene-analyzers-kuromoji-neologd.

When pushing a tag to git, TravisCI automatically creates a release.

# Using lightgbm

```
<dependency>
    <groupId>io.github.myui</groupId>
    <artifactId>lucene-analyzers-kuromoji-neologd</artifactId>
    <version>8.8.2-20200910.1</version>
</dependency>
```

# Release to Maven central

## Release to Staging

```
export LUCENE_VERSION=`cat LUCENE_VERSION`
export NEOLOGD_VERSION_DATE=`cat NEOLOGD_VERSION_DATE`
export RC_NUMBER=1

export VERSION_TAG="v${LUCENE_VERSION}-${NEOLOGD_VERSION_DATE}-${RC_NUMBER}"
git tag v8.8.2-20200910.1
git push origin v8.8.2-20200910.1
```

```sh
export NEXUS_PASSWD=xxxx
export PACKAGE_VERSION="${LUCENE_VERSION}-${NEOLOGD_VERSION_DATE}-${RC_NUMBER}"

mvn gpg:sign-and-deploy-file \
  -s ./settings.xml \
  -DpomFile=./lucene-analyzers-kuromoji-neologd.pom \
  -DrepositoryId=sonatype-nexus-staging \
  -Durl=https://oss.sonatype.org/service/local/staging/deploy/maven2/ \
  -Dfile=dist/lucene-analyzers-kuromoji-neologd-${PACKAGE_VERSION}.jar \
  -Dsources=dist/lucene-analyzers-kuromoji-neologd-${PACKAGE_VERSION}-sources.jar \
  -Djavadoc=dist/lucene-analyzers-kuromoji-neologd-${PACKAGE_VERSION}-javadoc.jar
```

## Release from Staging

1. Log in to [oss.sonatype.com](https://oss.sonatype.org/)
2. Click on “Staging Repositories” under Build Promotion
3. Verify the content of the repository (in the bottom pane), check it, click Close, confirm
4. Check the repo again, click “Release”
5. You shall now see your artifacts in the release repository created for you
6. In some hours, it should also appear in Maven Central
