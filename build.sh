#!/bin/bash

function set_ascii_color {
    red="\033[0;31m"
    green="\033[0;32m"
    yellow="\033[0;33m"
    nc="\033[0m"
}

function output {
    echo -e $1 $2 ${nc}
}

set_ascii_color
pwd=$(pwd)
build="$pwd/build"
resources="$pwd/resources"
perl_ver="5.38.2"
perl_build="$build/perl-$perl_ver"
perl_tarfile="$resources/perl-$perl_ver.tar.gz"

output ${green} "---- SCOT PERL builder packager "
output ${green} "---- pwd       = $pwd"
output ${green} "---- resources = $resources"
output ${green} "---- build     = $build"

function install_prereqs {
    output ${yellow} "Installing Apt Prerequisites"
    sudo DEBIAN_FRONTEND=noninteractive apt-get -y install libmagic-dev libexpat1-dev build-essential curl mysql-server libmysqlclient-dev postgresql postgresql-contrib libpq-dev krb5-config libkrb5-dev
}

function build_perl {
    output ${yellow} "Extracting PERL for building"
    if [[ ! -d $perl_build ]]; then
        mkdir -p $perl_build;
    fi
    tar xzf $perl_tarfile -C $build

    if [[ -r $perl_build/Makefile ]];then 
        output ${yellow} "Cleaning Perl Previous Perl Build"
        cd $perl_build
        make clean
        cd $pwd
    fi

    output ${yellow} "Configuring..."
    cd $perl_build
    ./Configure -des -Dprefix=/opt/perl -Dotherlibdirs=/opt/perl/lib/perl5

    output ${yellow} "Building..."
    make

    output ${yellow} "Testing..."
    make test

    output ${yellow} "Installing..."
    if [[ -d /opt/perl ]]; then
        sudo mv /opt/perl /opt/perl.bak
    fi

    sudo make install
    cd $pwd
}

function install_cpanm {
    output ${yellow} "Installing CPANMinus"
    curl -k -L https://cpanmin.us | /opt/perl/bin/perl - --sudo App::cpanminus
}

function install_modules {
    output ${yellow} "Manually installing Crypt::Curve25519"
    tar xzf $resources/Crypt-Curve25519-0.06.tar.gz -C $build
    cd $build/Crypt-Curve25519-0.06
    grep -rl "fmul" ./ | xargs sed -i 's/fmul/fixedvar/g'
    /opt/perl/bin/perl Makefile.PL
    make
    make test
    sudo -E make install
    cd $pwd

    output ${yellow} "Installing GSSAPI to see why it fails"
    /opt/perl/bin/cpanm -v --sudo GSSAPI

    output ${yellow} "Installing Modules with problematic network configs"
    # Install Net::HTTP while disabling specific tests that conflict w/ ssl cert
    NO_NETWORK_TESTING=1 /opt/perl/bin/cpanm --sudo Net::HTTP

    # Install LWP::Protocol::https while disabling specific tests that get blocked by IT Policy
    NO_NETWORK_TESTING=1 /opt/perl/bin/cpanm --sudo LWP::Protocol::https

    output ${yellow} "Installing WWW::Mechanize without tests due to hanging test"
    NO_NETWORK_TESTING=1 /opt/perl/bin/cpanm -n --force --sudo WWW::Mechanize

    output ${yellow} "Installing Test::mysqld without tests due to hanging test"
    NO_NETWORK_TESTING=1 /opt/perl/bin/cpanm -n --force --sudo Test::mysqld

    output ${yellow} "Installing Modules in cpanfile"
    # Install modules from cpanfile
    sudo -E /opt/perl/bin/cpanm --cpanfile $resources/cpanfile --installdeps .

    output ${yellow} "Force installing XML::RSS:Parser::Lite due to failing test"
    # has a failing test that does not affect operation
    /opt/perl/bin/cpanm -v --force --sudo XML::RSS::Parser::Lite

    output ${yellow} "Re-installing Lingua::EN::StopWords due to intermittent failures"
    # Try installing Lingua::EN::StopWords again due to intermittent failures
    NO_NETWORK_TESTING=1 /opt/perl/bin/cpanm -v --sudo Lingua::EN::StopWords

    output ${yellow} "Verbosely Trying to install LWP::ConsoleLogger::Easy"
    NO_NETWORK_TESTSING=1 /opt/perl/bin/cpanm -force -sudo LWP::ConsoleLogger::Easy

    output ${yellow} "Manually installing File::Magic"
    tar xzf $resources/File-Magic-0.01.tar.gz -C $build
    cd $build/File-Magic-0.01
    /opt/perl/bin/perl Makefile.PL
    make
    make test
    sudo -E make install
    cd $pwd
}

function verify_modules {
    output ${yellow} "Verifying Modules"
    modules=$(cat $resources/cpanfile | cut -d\' -f 2)
    modules="$modules File::Magic"
    missing=''

    for m in $modules; do
        /opt/perl/bin/perl -e "use $m;" 2>/dev/null
        if [[ "$?" != 0 ]]; then
            if [[ "$m" == "MooseX::AttributeShortcuts" ]];then
                echo "ignoring known error in $m"
            else
                missing="$missing $m"
            fi
        fi
    done

    failed=''
    if [[ "$missing" != "" ]]; then
        output ${red} "The Following Modules appear to be missing:"
        for x in $missing; do
            output ${red} "    $x"
            fm=$(retry_module $x)
            if [[ "$fm" != "" ]]; then
                failed="$failed $fm"
                output ${red} "Retry of $x failed"
            else
                output ${green} "Retry of $x worked"
            fi
        done

        if [[ "$failed" != "" ]]; then
            output ${red} "The Following Modules failed Retry"
            for y in $failed; do
                output ${red} "    $y"
            done
            output ${red} "Exiting build due to missing packages..."
            exit 1
        fi
    else
        output ${green} "All modules installed"
    fi
}

function retry_module {
    module="$1"
    /opt/perl/bin/cpanm -v --sudo $module
    /opt/perl/bin/perl -e "use $module;" 2>/dev/null
    if [[ "$?" != 0 ]]; then
        echo $module;
    fi
}

function copy_perl_for_debbuild {
    output ${yellow} "Copying Installed Perl to Debian build"
    mkdir -p $build/scot-perl/opt
    cp -rp /opt/perl $build/scot-perl/opt
    # tar -cf - /opt/perl | (cd $build/scot-perl; tar -xf -)
}

function build_deb_install_file {
    output ${yellow} "Building DEB install file"
    local files=$(find /opt/perl)
    for file in $files; do
        if [[ ! -d $file ]]; then
            local dir=$(dirname $file)
            local name=$(basename $file)
            echo "$name $dir" >> $build/scot-perl/DEBIAN/install
        fi
    done
}

function build_deb {
    output ${yellow} "Updating permissions of build dir"
    chmod -R 775 $build
    output ${yellow} "Packaging"
    if [[ ! -d  $build/deb_build ]];then
        mkdir -p $build/deb_build
    fi
    cd $build
    dpkg-deb --build scot-perl
    cd $pwd
    cp $build/scot-perl.deb $build/scot-perl-install/scot-perl.$perl_ver.deb
}

function wrap {
    output ${yellow} "Wrapping"
    tar czvf scot.perl.install.tar.gz -C $build ./scot-perl-install
}

function usage {
    output ${yellow} "Usage: $0 [-v] [-r]"
    output ${green}  "    -v      verify perl modules only"
    output ${green}  "    -r      rebuild deb from current /opt/perl state"
}

function replace_old_js {
    siteperl="/opt/perl/lib/site_perl/$perl_ver"
    miniondir="$siteperl/Mojolicious/Plugin/Minion/resources/public/minion"
    cp $resources/moment.min.js       $miniondir/moment/moment.js
    cp $resoutces/bootstrap.min.js    $miniondir/bootstrap/bootstrap.js
    cp $resoutces/bootstrap.min.css   $miniondir/bootstrap/bootstrap.css
    cp $resources/jquery-3.6.4.min.js $siteperl/Mojolicious/resources/public/mojo/jquery/jquery.js
}

while getopts "mprv" arg; do
    case $arg in
        m)
            echo "Rebuilding Modules..."
            install_modules
            exit 0
            ;;
        p)
            echo "Installing Prerequisite Debian packages..."
            install_prereqs
            exit 0
            ;;
        v)
            echo "Verify Modules..."
            verify_modules
            exit 0
            ;;
        r)
            echo "Rebuilding..."
            copy_perl_for_debbuild
            build_deb_install_file
            build_deb
            wrap
            exit 0
            ;;
        *)
            usage
            exit 0
            ;;
    esac
done

# attempt to suppress warning 
# that is filling logs
export no_proxy=$NO_PROXY

install_prereqs
build_perl
install_cpanm
install_modules
verify_modules
replace_old_js
copy_perl_for_debbuild
build_deb_install_file
build_deb
wrap

mkdir -p cpanm-logs
cp -r /root/.cpanm/work cpanm-logs
