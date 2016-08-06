#!/bin/bash -e

set -x


# check that filenames and filetypes for downloads match if they don't
# match, simply exit (hence no need for faking a return code)
filecheck() {
    local VERBOSE=

    local -r FILENAME="$1"
    local    EXPECTED=""

    if [[ ! -f "$FILENAME" ]]; then
        echo "Error: $FILENAME not found" >&2
        exit 1
    fi

    FILETYPE=`file $FILENAME`

    if [[ `basename $FILENAME` == *tgz || `basename $FILENAME` == *tar.gz ]]; then
        EXPECTED="gzip compressed data"
    fi

    if [[ `basename $FILENAME` == *.deb ]]; then
        EXPECTED="Debian binary package"
    fi

    if [[ `basename $FILENAME` == *disk*img ]]; then
        EXPECTED="QEMU QCOW"
    fi

    if [[ `basename $FILENAME` =~ initrd ]]; then
        EXPECTED="data"
    fi

    if [[ `basename $FILENAME` == *.iso ]]; then
        EXPECTED="CD-ROM filesystem data"
    fi

    if [[ `basename $FILENAME` =~ vmlinuz ]]; then
        EXPECTED="Linux kernel x86 boot executable bzImage"
    fi

    if [[ -n "$EXPECTED" ]] && [[ ! "$FILETYPE" =~ "$EXPECTED" ]]; then
        echo "Error: $FILENAME is not of type $EXPECTED" >&2
        exit 1
    else
        if [[ -n "$VERBOSE" ]]; then
            if [[ -n "$EXPECTED" ]]; then
                echo "pass : expected $EXPECTED, got $FILETYPE"
            else
                echo "pass : no check implemented for $FILENAME"
            fi
        fi
    fi
}


# Define the appropriate version of each binary to grab/build
VER_KIBANA=2581d314f12f520638382d23ffc03977f481c1e4
# newer versions of Diamond depend upon dh-python which isn't in precise/12.04
VER_DIAMOND=f33aa2f75c6ea2dfbbc659766fe581e5bfe2476d
VER_ESPLUGIN=9c032b7c628d8da7745fbb1939dcd2db52629943

if [[ -f ./proxy_setup.sh ]]; then
  . ./proxy_setup.sh
fi


# we now define CURL previously in proxy_setup.sh (called from
# setup_chef_server which calls this script. Default definition is
# CURL=curl
if [ -z "$CURL" ]; then
  CURL=curl
fi


# Checked CURL
# usage: ccurl filename (new filename)
#
# The file is downloaded with default filename, checked for file type
# matching, then if a second parameter was passed, renamed to that
ccurl() {
    $CURL -L -O $1
    # filecheck will exit if a problem, otherwise it's too much noise
    set +x
    filecheck `basename $1`
    if [[ -n "$2" ]]; then
        mv `basename $1` $2
    fi
    set -x
}


DIR=`dirname $0`

mkdir -p $DIR/bins
pushd $DIR/bins/

# Install tools needed for packaging
apt-get -y install git rubygems make pbuilder python-mock python-configobj python-support cdbs python-all-dev python-stdeb libmysqlclient-dev libldap2-dev
if [ -z `gem list --local fpm | grep fpm | cut -f1 -d" "` ]; then
  gem install fpm --no-ri --no-rdoc
fi

# Fetch chef client and server debs
CHEF_CLIENT_URL=https://opscode-omnibus-packages.s3.amazonaws.com/ubuntu/12.04/x86_64/chef_11.14.6-1_amd64.deb
CHEF_SERVER_URL=https://opscode-omnibus-packages.s3.amazonaws.com/ubuntu/12.04/x86_64/chef-server_11.0.12-1.ubuntu.12.04_amd64.deb
if [ ! -f chef-client.deb ]; then
   ccurl  ${CHEF_CLIENT_URL} chef-client.deb
fi

if [ ! -f chef-server.deb ]; then
   ccurl  ${CHEF_SERVER_URL} chef-server.deb
fi
FILES="chef-client.deb chef-server.deb $FILES"

# Build kibana3 installable bundle
if [ ! -f kibana3.tgz ]; then
    git clone https://github.com/elasticsearch/kibana.git kibana3
    cd kibana3/src
    git archive --output ../../kibana3.tgz --prefix kibana3/ $VER_KIBANA
    cd ../..
    rm -rf kibana3
fi
FILES="kibana3.tgz $FILES"

# any pegged gem versions
REV_elasticsearch="0.2.0"

# Grab plugins for fluentd
for i in elasticsearch tail-multiline tail-ex record-reformer rewrite; do
    if [ ! -f fluent-plugin-${i}.gem ]; then
        PEG=REV_${i}
        if [[ ! -z ${!PEG} ]]; then
            VERS="-v ${!PEG}"
        else
            VERS=""
        fi
        gem fetch fluent-plugin-${i} ${VERS}
        mv fluent-plugin-${i}-*.gem fluent-plugin-${i}.gem
    fi
    FILES="fluent-plugin-${i}.gem $FILES"
done

# Fetch the cirros image for testing
if [ ! -f cirros-0.3.2-x86_64-disk.img ]; then
    ccurl http://download.cirros-cloud.net/0.3.2/cirros-0.3.2-x86_64-disk.img
fi
FILES="cirros-0.3.2-x86_64-disk.img $FILES"

# Grab the Ubuntu 12.04 installer image
if [ ! -f ubuntu-12.04-mini.iso ]; then
    # Download this ISO to get the latest kernel/X LTS stack installer
    #$CURL -o ubuntu-12.04-mini.iso http://archive.ubuntu.com/ubuntu/dists/precise-updates/main/installer-amd64/current/images/raring-netboot/mini.iso
    ccurl  http://archive.ubuntu.com/ubuntu/dists/precise/main/installer-amd64/current/images/netboot/mini.iso ubuntu-12.04-mini.iso
fi
FILES="ubuntu-12.04-mini.iso $FILES"

# Grab the CentOS 6 PXE boot images
if [ ! -f centos-6-initrd.img ]; then
    ccurl  http://mirror.net.cen.ct.gov/centos/6/os/x86_64/images/pxeboot/initrd.img centos-6-initrd.img
fi
FILES="centos-6-initrd.img $FILES"

if [ ! -f centos-6-vmlinuz ]; then
    ccurl  http://mirror.net.cen.ct.gov/centos/6/os/x86_64/images/pxeboot/vmlinuz centos-6-vmlinuz
fi
FILES="centos-6-vmlinuz $FILES"

# Make the diamond package
if [ ! -f diamond.deb ]; then
    git clone https://github.com/BrightcoveOS/Diamond.git
    cd Diamond
    git checkout $VER_DIAMOND
    make builddeb
    VERSION=`cat version.txt`
    cd ..
    mv Diamond/build/diamond_${VERSION}_all.deb diamond.deb
    rm -rf Diamond
fi
FILES="diamond.deb $FILES"

# Snag elasticsearch
ES_VER=1.1.1
if [ ! -f elasticsearch-${ES_VER}.deb ]; then
    ccurl https://download.elasticsearch.org/elasticsearch/elasticsearch/elasticsearch-${ES_VER}.deb
fi
if [ ! -f elasticsearch-${ES_VER}.deb.sha1.txt ]; then
    ccurl https://download.elasticsearch.org/elasticsearch/elasticsearch/elasticsearch-${ES_VER}.deb.sha1.txt
fi
if [[ `shasum elasticsearch-${ES_VER}.deb` != `cat elasticsearch-${ES_VER}.deb.sha1.txt` ]]; then
    echo "SHA mismatch detected for elasticsearch ${ES_VER}!"
    echo "Have: `shasum elasticsearch-${ES_VER}.deb`"
    echo "Expected: `cat elasticsearch-${ES_VER}.deb.sha1.txt`"
    exit 1
fi

FILES="elasticsearch-${ES_VER}.deb elasticsearch-${ES_VER}.deb.sha1.txt $FILES"

if [ ! -f elasticsearch-plugins.tgz ]; then
    git clone https://github.com/mobz/elasticsearch-head.git
    cd elasticsearch-head
    git archive --output ../elasticsearch-plugins.tgz --prefix head/_site/ $VER_ESPLUGIN
    cd ..
    rm -rf elasticsearch-head
fi
FILES="elasticsearch-plugins.tgz $FILES"

# Fetch pyrabbit
if [ ! -f pyrabbit-1.0.1.tar.gz ]; then
    ccurl https://pypi.python.org/packages/source/p/pyrabbit/pyrabbit-1.0.1.tar.gz
fi
FILES="pyrabbit-1.0.1.tar.gz $FILES"

# Build graphite packages
GRAPHITE_CARBON_VER="0.9.13"
GRAPHITE_WHISPER_VER="0.9.13"
GRAPHITE_WEB_VER="0.9.13"
if [ ! -f python-carbon_${GRAPHITE_CARBON_VER}_all.deb ] || [ ! -f python-whisper_${GRAPHITE_WHISPER_VER}_all.deb ] || [ ! -f python-graphite-web_${GRAPHITE_WEB_VER}_all.deb ]; then
    ccurl  http://pypi.python.org/packages/source/c/carbon/carbon-${GRAPHITE_CARBON_VER}.tar.gz
    ccurl  http://pypi.python.org/packages/source/w/whisper/whisper-${GRAPHITE_WHISPER_VER}.tar.gz
    ccurl  http://pypi.python.org/packages/source/g/graphite-web/graphite-web-${GRAPHITE_WEB_VER}.tar.gz
    tar zxf carbon-${GRAPHITE_CARBON_VER}.tar.gz
    tar zxf whisper-${GRAPHITE_WHISPER_VER}.tar.gz
    tar zxf graphite-web-${GRAPHITE_WEB_VER}.tar.gz
    fpm --python-install-bin /opt/graphite/bin -s python -t deb carbon-${GRAPHITE_CARBON_VER}/setup.py
    fpm --python-install-bin /opt/graphite/bin  -s python -t deb whisper-${GRAPHITE_WHISPER_VER}/setup.py
    fpm --python-install-lib /opt/graphite/webapp -s python -t deb graphite-web-${GRAPHITE_WEB_VER}/setup.py
    rm -rf carbon-${GRAPHITE_CARBON_VER} carbon-${GRAPHITE_CARBON_VER}.tar.gz whisper-${GRAPHITE_WHISPER_VER} whisper-${GRAPHITE_WHISPER_VER}.tar.gz graphite-web-${GRAPHITE_WEB_VER} graphite-web-${GRAPHITE_WEB_VER}.tar.gz
fi
FILES="python-carbon_${GRAPHITE_CARBON_VER}_all.deb python-whisper_${GRAPHITE_WHISPER_VER}_all.deb python-graphite-web_${GRAPHITE_WEB_VER}_all.deb $FILES"

# Build the zabbix packages
if [ ! -f zabbix-agent.tar.gz ] || [ ! -f zabbix-server.tar.gz ]; then
    ccurl http://sourceforge.net/projects/zabbix/files/ZABBIX%20Latest%20Stable/2.2.2/zabbix-2.2.2.tar.gz
    tar zxf zabbix-2.2.2.tar.gz
    rm -rf /tmp/zabbix-install && mkdir -p /tmp/zabbix-install
    cd zabbix-2.2.2
    ./configure --prefix=/tmp/zabbix-install --enable-agent --with-ldap
    make install
    tar zcf zabbix-agent.tar.gz -C /tmp/zabbix-install .
    rm -rf /tmp/zabbix-install && mkdir -p /tmp/zabbix-install
    ./configure --prefix=/tmp/zabbix-install --enable-server --with-mysql --with-ldap
    make install
    cp -a frontends/php /tmp/zabbix-install/share/zabbix/
    cp database/mysql/* /tmp/zabbix-install/share/zabbix/
    tar zcf zabbix-server.tar.gz -C /tmp/zabbix-install .
    rm -rf /tmp/zabbix-install
    cd ..
    cp zabbix-2.2.2/zabbix-agent.tar.gz .
    cp zabbix-2.2.2/zabbix-server.tar.gz .
    rm -rf zabbix-2.2.2 zabbix-2.2.2.tar.gz
fi
FILES="zabbix-agent.tar.gz zabbix-server.tar.gz $FILES"

# Get some python libs 
if [ ! -f python-requests-aws_0.1.5_all.deb ]; then
    fpm -s python -t deb -v 0.1.5 requests-aws
fi
FILES="python-requests-aws_0.1.5_all.deb $FILES"

# Get the 3.1.3 version of supervisor
if [ ! -f supervisor_3.1.3_all.deb ]; then
    fpm -s python -t deb -n supervisor -v 3.1.3 --python-install-bin /usr/bin --python-install-lib /usr/local/lib/python2.7/dist-packages supervisor
fi
FILES="supervisor_3.1.3_all.deb $FILES"

popd
