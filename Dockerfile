FROM debian:bookworm AS perl-build

WORKDIR /app
ENV DEBIAN_FRONTEND=noninteractive \
    DEBCONF_NONINTERACTIVE_SEEN=true

# Install necessary packages
RUN apt-get update -y && \
    apt-get install apache2 \
                    apache2-utils \
                    bc \
                    build-essential \
                    curl \
                    dos2unix \
                    gcc \
                    krb5-doc \
                    krb5-config \
                    krb5-user \
                    libexpat1-dev \
                    libexpat1-dev\
                    libgeoip-dev \
                    libgmp3-dev \
                    libgssapi-krb5-2 \
                    libimlib2 \
                    libimlib2-dev \
                    libkrb5-3 \
                    libkrb5-dev \
                    libkrb5support0 \
                    libmagic-dev \
                    libmagic-ocaml-dev \
                    libmagic1 \
                    libmagick++-6-headers \
                    libmagick++-6.q16-dev \
                    libmagick++-dev \
                    libmagickcore-6-headers \
                    libmagickcore-6.q16-dev \ 
                    libmagickcore-dev \
                    libmagickwand-6-headers \
                    libmagickwand-6.q16-dev \
                    libmagickwand-dev \
                    libmagics++-dev \
                    libmagics++-metview-dev \
                    libmariadb-dev \ 
                    libmariadb-dev-compat \
                    libmaxminddb-dev \
                    libmaxminddb0 \
                    libpq-dev \ 
                    libsqlite3-0 \
                    libsqlite3-dev \
                    libssl-dev \
                    make \
                    mmdb-bin \
                    openssl \
                    postgresql-server-dev-all \
                    sudo \
                    zlib1g \
                    zlib1g-dev \
                    -y

COPY . /app

RUN ./build.sh

RUN ls -ltrah /app

FROM debian:bookworm

WORKDIR /app
ENV DEBIAN_FRONTEND=noninteractive \
    DEBCONF_NONINTERACTIVE_SEEN=true

# Add required packages
RUN apt-get update -y && \
    apt-get install curl sudo lsb-release inetutils-tools sqlite3 vim -y 

COPY --from=perl-build /app/scot.perl.install.tar.gz /app/scot.perl.install.tar.gz

# Unzip and install scot-perl
RUN tar -xzf /app/scot.perl.install.tar.gz && \
    apt-get install ./scot-perl-install/scot-perl.5.38.2.deb -y --fix-missing
