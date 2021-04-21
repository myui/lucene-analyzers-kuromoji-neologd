#!/bin/bash

# The original script: https://github.com/kazuhira-r/kuromoji-with-mecab-neologd-buildscript

# Exit script if you try to use an uninitialized variable.
set -o nounset
# Exit script if a statement returns a non-true return value.
set -o errexit

SCRIPT_NAME=$0
KUROMOJI_NEOLOGD_BUILD_WORK_DIR=`pwd`

########## Define Functions ##########

logging() {
    LABEL=$1
    LEVEL=$2
    MESSAGE=$3

    TIME=`date +"%Y-%m-%d %H:%M:%S"`

    echo "### [$TIME] [$LABEL] [$LEVEL] $MESSAGE"
}

usage() {
    cat <<EOF
Usage: ${SCRIPT_NAME} [options...]
  options:
    -d ... specify NEologd version date. (format: YYYYMMDD, default: latest dictionary on the master branch)
    -L ... Lucene Version Tag, use git checkout argument. (default: ${LUCENE_VERSION_TAG}) 
    -h ... print this help.

Example: ${SCRIPT_NAME} -N v0.0.7 -L releases/lucene-solr/8.8.2
EOF
}

########## Default & Fixed Values ##########

## MeCab
MECAB_VERSION=mecab-0.996
MECAB_INSTALL_DIR=${KUROMOJI_NEOLOGD_BUILD_WORK_DIR}/mecab

## mecab-ipadic-NEologd
MAX_BASEFORM_LENGTH=15

## mecab-ipadic-NEologd Target Tag
MECAB_IPADIC_NEOLOGD_TAG=master

## Lucene Target Tag
LUCENE_VERSION=8.8.2
LUCENE_VERSION_TAG=releases/lucene-solr/${LUCENE_VERSION}

## Kuromoji build max heapsize
KUROMOJI_BUILD_MAX_HEAPSIZE=5g

## generated JAR file output directory
JAR_FILE_OUTPUT_DIRECTORY=.

## Source Package
DEFAULT_KUROMOJI_PACKAGE=org.apache.lucene.analysis.ja
REDEFINED_KUROMOJI_PACKAGE=org.apache.lucene.analysis.ja.neologd

########## Arguments Process ##########

while getopts d:L:N:h OPTION
do
    case $OPTION in
        d)
            yyyymmdd="^[0-9]{8}$"
            if [[ ! ${OPTARG} =~ $yyyymmdd ]]; then
              usage
              exit 1
            fi
            MECAB_IPADIC_NEOLOGD_TAG=${OPTARG:0:4}-${OPTARG:4:2}-${OPTARG:6};;
		L)
            LUCENE_VERSION_TAG=${OPTARG};;
		h)
            usage
            exit 0;;
        \?)
            usage
            exit 1;;
    esac
done

logging main INFO 'START.'

cat <<EOF

####################################################################
applied build options.

[Installed MeCab Version                     ]    ... ${MECAB_VERSION}
[mecab-ipadic-NEologd Tag                (-N)]    ... ${MECAB_IPADIC_NEOLOGD_TAG}
[Lucene Version Tag                      (-L)]    ... ${LUCENE_VERSION_TAG}

####################################################################

EOF

sleep 3

########## Setup mecab ##########

if [ ! -d ${JAR_FILE_OUTPUT_DIRECTORY} ]; then
    logging pre-check ERROR "directory[${JAR_FILE_OUTPUT_DIRECTORY}], not exits."
    exit 1
fi

if [ ! `which mecab` ]; then
    if [ ! -e ${MECAB_INSTALL_DIR}/bin/mecab ]; then
        logging mecab INFO 'MeCab Install Local.'

        if [ ! -e ${MECAB_VERSION}.tar.gz ]; then
            curl 'https://drive.google.com/uc?export=download&id=0B4y35FiV1wh7cENtOXlicTFaRUE' -L -o ${MECAB_VERSION}.tar.gz
        fi
        tar -zxf ${MECAB_VERSION}.tar.gz
        cd ${MECAB_VERSION}

        if [ ! -e ${MECAB_INSTALL_DIR} ]; then
            mkdir -p ${MECAB_INSTALL_DIR}
        fi

        ./configure --prefix=${MECAB_INSTALL_DIR}
        make
        make install
    fi

    PATH=${MECAB_INSTALL_DIR}/bin:${PATH}
fi

cd ${KUROMOJI_NEOLOGD_BUILD_WORK_DIR}

########## Setup Neologd dict ##########

logging mecab-ipadic-NEologd INFO 'Download mecab-ipadic-NEologd.'

if [ ! -e mecab-ipadic-neologd ]; then
    git clone https://github.com/neologd/mecab-ipadic-neologd.git
else
    cd mecab-ipadic-neologd

    if [ -d build ]; then
        rm -rf build
    fi

    git checkout master
    git fetch origin
    git reset --hard origin/master
    git pull --tags
    cd ..
fi

cd mecab-ipadic-neologd

if [ "${MECAB_IPADIC_NEOLOGD_TAG}" != "master" ]; then
    logging mecab-ipadic_NEologd INFO "Use dictionary published on the nearest date after ${MECAB_IPADIC_NEOLOGD_TAG} (inclusive)"
    NEAREST_COMMIT_DATE=`git log --pretty=format:%cd --date=short --after=${MECAB_IPADIC_NEOLOGD_TAG} --reverse | head -n 1`
    MECAB_IPADIC_NEOLOGD_TAG=`git log -1 --pretty=format:%H --after="${NEAREST_COMMIT_DATE}T00:00:00Z" --until="${NEAREST_COMMIT_DATE}T23:59:59Z"`

    if [ -z "$MECAB_IPADIC_NEOLOGD_TAG" ]; then
        logging mecab-ipadic_NEologd ERROR "NEologd version date specified by the '-d' option is invalid."
        exit 1
    fi

    MECAB_IPADIC_NEOLOGD_MASTER_COMMIT_HASH=`git rev-parse master`
    if [ "${MECAB_IPADIC_NEOLOGD_TAG}" == "${MECAB_IPADIC_NEOLOGD_MASTER_COMMIT_HASH}" ]; then
        logging mecab-ipadic_NEologd INFO "NEologd version date specified by the '-d' option corresponds to the master branch."
    else
        git checkout ${MECAB_IPADIC_NEOLOGD_TAG}

        if [ $? -ne 0 ]; then
            logging mecab-ipadic-NEologd ERROR "git checkout[${MECAB_IPADIC_NEOLOGD_TAG}] failed. Please re-run after execute 'rm -f mecab-ipadic-neologd'"
            exit 1
        fi

        rm -f seed/mecab-user-dict-seed.*

        # get the seed file
        SEED_COMMIT_HASH=`cat ChangeLog | grep -m 1 'commit: ' | perl -wp -e 's!^.*/([0-9a-z]+).*$!$1!'`
        SEED_FILENAME=`cat ChangeLog | grep -m 1 'seed/' | perl -wp -e 's!^.*seed/(.+\.csv\.xz).*$!$1!'`
        if [ -z "$SEED_COMMIT_HASH" -o -z "$SEED_FILENAME" ]; then
            logging mecab-ipadic_NEologd ERROR "NEologd changelog cannot be parsed, and hence seed file name and its commit hash cannot be found."
            exit 1
        fi
        SEED_DOWNLOAD_URL=https://github.com/neologd/mecab-ipadic-neologd/raw/${SEED_COMMIT_HASH}/seed/${SEED_FILENAME}

        logging mecab-ipadic_NEologd INFO "Download mecab-user-dict-seed file: ${SEED_DOWNLOAD_URL}"
        wget $SEED_DOWNLOAD_URL -O seed/$SEED_FILENAME
    fi
fi

libexec/make-mecab-ipadic-neologd.sh -L ${MAX_BASEFORM_LENGTH}

DIR=`pwd`

NEOLOGD_BUILD_DIR=`find ${DIR}/build/mecab-ipadic-* -maxdepth 1 -type d`
NEOLOGD_DIRNAME=`basename ${NEOLOGD_BUILD_DIR}`
NEOLOGD_VERSION_DATE=`echo ${NEOLOGD_DIRNAME} | perl -wp -e 's!.+-(\d+)!$1!'`

cd ${KUROMOJI_NEOLOGD_BUILD_WORK_DIR}

########## Setup Lucene ##########

logging lucene INFO 'Cloning Lucene Repository ..'
if [ ! -e lucene-solr ]; then
    git clone --branch ${LUCENE_VERSION_TAG} --depth 1 https://github.com/apache/lucene-solr.git
fi
cd lucene-solr

if [ "$(git symbolic-ref -q --short HEAD || git describe --tags)" != "${LUCENE_VERSION_TAG}" ]; then
    cd ..
    rm -rf lucene-solr
    git clone --branch ${LUCENE_VERSION_TAG} --depth 1 https://github.com/apache/lucene-solr.git
    cd lucene-solr
fi

git checkout ${LUCENE_VERSION_TAG}
git reset --hard ${LUCENE_VERSION_TAG}
git status -s | grep '^?' | perl -wn -e 's!^\?+ ([^ ]+)!git clean -df $1!; system("$_")'
ant clean

LUCENE_SRC_DIR=`pwd`

if [ $? -ne 0 ]; then
    logging lucene ERROR "git checkout[${LUCENE_VERSION_TAG}] failed. Please re-run after execute 'rm -f lucene-solr'"
    exit 1
fi

########## Build Lucene ##########

cd lucene

# workaround for https://support.sonatype.com/hc/en-us/articles/360041287334
sed -ie 's|http://repo1.maven.org/maven2|https://repo1.maven.org/maven2|' common-build.xml

ant ivy-bootstrap

cd analysis/kuromoji
KUROMOJI_SRC_DIR=`pwd`

git checkout build.xml

logging lucene INFO 'Build Lucene Kuromoji, with mecab-ipadic-NEologd.'
mkdir -p ${LUCENE_SRC_DIR}/lucene/build/analysis/kuromoji
cp -Rp ${NEOLOGD_BUILD_DIR} ${LUCENE_SRC_DIR}/lucene/build/analysis/kuromoji

if [ -e ${LUCENE_SRC_DIR}/lucene/version.properties ]; then
    perl -wp -i -e "s!^version.suffix=(.+)!version.suffix=${NEOLOGD_VERSION_DATE}-SNAPSHOT!" ${LUCENE_SRC_DIR}/lucene/version.properties
fi
perl -wp -i -e "s!\"dev.version.suffix\" value=\"SNAPSHOT\"!\"dev.version.suffix\" value=\"${NEOLOGD_VERSION_DATE}-SNAPSHOT\"!" ${LUCENE_SRC_DIR}/lucene/common-build.xml
perl -wp -i -e 's!<project name="analyzers-kuromoji"!<project name="analyzers-kuromoji-neologd"!' build.xml
perl -wp -i -e 's!maxmemory="[^"]+"!maxmemory="'${KUROMOJI_BUILD_MAX_HEAPSIZE}'"!' build.xml

if [ "${REDEFINED_KUROMOJI_PACKAGE}" != "${DEFAULT_KUROMOJI_PACKAGE}" ]; then
    logging lucene INFO "redefine package [${DEFAULT_KUROMOJI_PACKAGE}] => [${REDEFINED_KUROMOJI_PACKAGE}]."

    ORIGINAL_SRC_DIR=`echo ${DEFAULT_KUROMOJI_PACKAGE} | perl -wp -e 's!\.!/!g'`
    NEW_SRC_DIR=`echo ${REDEFINED_KUROMOJI_PACKAGE} | perl -wp -e 's!\.!/!g'`

    test -d ${KUROMOJI_SRC_DIR}/src/java/${NEW_SRC_DIR} && rm -rf ${KUROMOJI_SRC_DIR}/src/java/${NEW_SRC_DIR}
    mkdir -p ${KUROMOJI_SRC_DIR}/src/java/${NEW_SRC_DIR}
    find ${KUROMOJI_SRC_DIR}/src/java/${ORIGINAL_SRC_DIR} -mindepth 1 -maxdepth 1 -not -path ${KUROMOJI_SRC_DIR}/src/java/${NEW_SRC_DIR} | xargs -I{} mv {} ${KUROMOJI_SRC_DIR}/src/java/${NEW_SRC_DIR}
    find ${KUROMOJI_SRC_DIR}/src/java/${NEW_SRC_DIR} -type f | xargs perl -wp -i -e "s!${DEFAULT_KUROMOJI_PACKAGE//./\\.}!${REDEFINED_KUROMOJI_PACKAGE}!g"

    test -d ${KUROMOJI_SRC_DIR}/src/resources/${NEW_SRC_DIR} && rm -rf ${KUROMOJI_SRC_DIR}/src/resources/${NEW_SRC_DIR}
    mkdir -p ${KUROMOJI_SRC_DIR}/src/resources/${NEW_SRC_DIR}
    find ${KUROMOJI_SRC_DIR}/src/resources/${ORIGINAL_SRC_DIR} -mindepth 1 -maxdepth 1 -not -path ${KUROMOJI_SRC_DIR}/src/resources/${NEW_SRC_DIR} | xargs -I{} mv {} ${KUROMOJI_SRC_DIR}/src/resources/${NEW_SRC_DIR}

    test -d ${KUROMOJI_SRC_DIR}/src/tools/java/${NEW_SRC_DIR} && rm -rf ${KUROMOJI_SRC_DIR}/src/tools/java/${NEW_SRC_DIR}
    mkdir -p ${KUROMOJI_SRC_DIR}/src/tools/java/${NEW_SRC_DIR}
    find ${KUROMOJI_SRC_DIR}/src/tools/java/${ORIGINAL_SRC_DIR} -mindepth 1 -maxdepth 1 -not -path ${KUROMOJI_SRC_DIR}/src/tools/java/${NEW_SRC_DIR} | xargs -I{} mv {} ${KUROMOJI_SRC_DIR}/src/tools/java/${NEW_SRC_DIR}
    find ${KUROMOJI_SRC_DIR}/src/tools/java/${NEW_SRC_DIR} -type f | xargs perl -wp -i -e "s!${DEFAULT_KUROMOJI_PACKAGE//./\\.}!${REDEFINED_KUROMOJI_PACKAGE}!g"

    perl -wp -i -e "s!${ORIGINAL_SRC_DIR}!${NEW_SRC_DIR}!g" build.xml
    perl -wp -i -e "s!${DEFAULT_KUROMOJI_PACKAGE//./\\.}!${REDEFINED_KUROMOJI_PACKAGE}!g" build.xml
fi

ant -Dipadic.version=${NEOLOGD_DIRNAME} -Ddict.encoding=utf-8 regenerate
if [ $? -ne 0 ]; then
    logging lucene ERROR 'Dictionary Build Fail.'
    exit 1
fi

ant jar-core jar-src javadocs
if [ $? -ne 0 ]; then
    logging lucene ERROR 'Kuromoji Build Fail.'
    exit 1
fi

########## Packacing lucene-analyzers-kuromoji-neologd ##########

cd ${KUROMOJI_NEOLOGD_BUILD_WORK_DIR}

mkdir -p ${KUROMOJI_NEOLOGD_BUILD_WORK_DIR}/dist

logging main INFO 'Packaing lucene-analyzers-kuromoji-neologd jars'

mv ${LUCENE_SRC_DIR}/lucene/build/analysis/kuromoji/lucene-analyzers-kuromoji* .

SRC_JAR_NAME=`ls -1 lucene-analyzers-kuromoji-neologd-*-SNAPSHOT.jar`
DST_JAR_NAME=`echo ${SRC_JAR_NAME} | perl -wp -e 's/(.+)-SNAPSHOT(.+)/$1$2/'`
mv $SRC_JAR_NAME ${KUROMOJI_NEOLOGD_BUILD_WORK_DIR}/dist/$DST_JAR_NAME

SRC_SOURCE_JAR_NAME=`ls -1 lucene-analyzers-kuromoji-neologd-*-SNAPSHOT-src.jar`
DST_SOURCE_JAR_NAME=`echo ${SRC_SOURCE_JAR_NAME} | perl -wp -e 's/(.+)-SNAPSHOT(.+)/$1$2/'`
mv $SRC_SOURCE_JAR_NAME ${KUROMOJI_NEOLOGD_BUILD_WORK_DIR}/dist/$DST_SOURCE_JAR_NAME

SRC_DOC_JAR_NAME=`ls -1 lucene-analyzers-kuromoji-neologd-*-SNAPSHOT-javadoc.jar`
DST_DOC_JAR_NAME=`echo ${SRC_DOC_JAR_NAME} | perl -wp -e 's/(.+)-SNAPSHOT(.+)/$1$2/'`
mv $SRC_DOC_JAR_NAME ${KUROMOJI_NEOLOGD_BUILD_WORK_DIR}/dist/$DST_DOC_JAR_NAME

logging main INFO "Successfully built => ${DST_JAR_NAME}, ${DST_SOURCE_JAR_NAME}"
