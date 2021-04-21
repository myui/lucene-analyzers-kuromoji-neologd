#
# Licensed to the Apache Software Foundation (ASF) under one
# or more contributor license agreements.  See the NOTICE file
# distributed with this work for additional information
# regarding copyright ownership.  The ASF licenses this file
# to you under the Apache License, Version 2.0 (the
# "License"); you may not use this file except in compliance
# with the License.  You may obtain a copy of the License at
#
#   http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing,
# software distributed under the License is distributed on an
# "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
# KIND, either express or implied.  See the License for the
# specific language governing permissions and limitations
# under the License.
#

# How to build Docker image from this Dockerfile
# $ docker build -f ./Dockerfile -t lucene-analyzers-kuromoji-neologd:latest .
# $ docker run -it --rm lucene-analyzers-kuromoji-neologd:latest bash

FROM openjdk:8-jdk-slim-buster

MAINTAINER Makoto Yui <myui@apache.org>

WORKDIR /work

COPY ./scripts/build.sh lucene-analyzers-kuromoji-neologd.pom ./

RUN set -eux && \
    apt-get update && \
    mkdir -p /usr/share/man/man1 && \
    apt-get install --no-install-recommends -y build-essential && \
    apt-get install --no-install-recommends -y vim maven ant curl git file binutils && \
    apt-get clean && rm -rf /var/lib/apt/lists/*

CMD ["bash"]
