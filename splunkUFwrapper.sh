#!/bin/sh
#
# SecIT, Vladimir Had
# 1. run LDAPSEARCH against LDAP_INPUT_PARAM and output values in LDAP_OUTPUT_PARAM
# 2. LDAP_OUTPUT_PARAM is statically extracted to separate variables as arrays in BASH are not supported by all shells
# 3. Values from LDAP_OUTPUT_PARAM are greped against ROUTING_MAP to find defined destination
#
# The version in splk_routing_map should be manually increased when doing updates to the routing map to track the issues
# splk_routing_map.conf structure:
# version:n
# param1,param2,destination
#
# splk_override.conf structure (one line):
# hostname

LDAP_HOST="localhost"
LDAP_PORT="389"
LDAP_BASEDN="dc=eu-west-2,dc=compute,dc=internal"
LDAP_INPUT_PARAM="(hostname=`hostname`)"
LDAP_OUTPUT_PARAM="uidNumber gidNumber"

BASEDIR=`dirname $0`
ROUTING_MAP="${BASEDIR}/splk_routing_map.conf"
OVERRIDE_FILE="${BASEDIR}/splk_override.conf"
DEPLOYMENTCLIENT_CONF="${BASEDIR}/../../splunkforwarder/etc/system/default/deploymentclient.conf"

USE_STDOUT=1
USE_LOGGER=1

# logging function
_logme() {
        if [ $USE_STDOUT ]; then
               echo "script=$0 arch=$ARCH timestamp=\"$(date)\" hostname=$($HOSTNAME) $@"
        fi
        if [ $USE_LOGGER ]; then
               LOGGER="logger"
               $LOGGER "script=$0 arch=$ARCH timestamp=\"$(date)\" hostname=$($HOSTNAME) $@"
        fi
}

# do not depend on which(1) - from Splunk TA nix
_queryCmd() {
        for dir in `echo $PATH | sed 's/:/ /g'`; do
               if [ -x $dir/$1 ]; then
                       return 0
               fi
        done
        _logme "func=_prolog msg=\"Mandatory command not found" cmd=\"$1\" path=\"$PATH\"" status=ko"
        exit 1
}

# test connection using nc to deployment server. $1 is ip/host, $2 is port
_testDeploymentServer(){
        _queryCmd nc
        #use netcat to determine if the deployment server is reachable
        nc -w 1 -z $1 $2 2&>/dev/null
        if [ $? != "0" ]; then
               _logme "func=_testDeploymentServer msg=\"The Deployment server '$1:$2' not reachable\" status=ko"
        else
               _logme "func=_testDeploymentServer msg=\"The Deployment server '$1:$2' available\" status=ok"
        fi
}

# get DS from LDAP.
_getDeploymentServer() {
        FILE=$($MKTEMP)
        if [ $FILE ]; then
               $LDAPSEARCH_CMD > $FILE
               LDAP_ERROR_CODE=$?
               if [ $LDAP_ERROR_CODE -gt 0 ]; then
                       _logme "func=_getDeploymentServer ldaperror=$LDAP_ERROR_CODE msg=\"cannot connect to LDAP\" ldapsearch=\"$LDAPSEARCH_CMD\" status=ko"
               else
                       #dont use bash array as it is not supported by old s=
hells
                       HOSTCOUNTRY=$(grep ^uidNumber $FILE | $CUT -d' ' -f2-)
                       INFRADOMAIN=$(grep ^gidNumber $FILE | $CUT -d' ' -f2-)
                       if [ "$HOSTCOUNTRY" ] && [ "$INFRADOMAIN" ]; then
                               if [ ! -f $ROUTING_MAP ]; then
                                      _logme "func=_getDeploymentServer msg=\"cannot locate $ROUTING_MAP\" dir=$(pwd) status=ko"
                               else
                                      ROUTING_MAP_VERSION=$(grep version $ROUTING_MAP 2>/dev/null)
                                      $(grep -q "^$INFRADOMAIN,$HOSTCOUNTRY" $ROUTING_MAP 2>/dev/null)
                                      if [ $? = 0 ]; then
                                              #uniq in case there are dupli=
cates
                                              SPLK_DEST_DS=$(grep "^$INFRADOMAIN,$HOSTCOUNTRY" $ROUTING_MAP | $CUT -d, -f3 | sort | uniq | head -n 1=
)
                                              _logme "func=_getDeploymentServer msg=\"DS found\" ds=$SPLK_DEST_DS HOSTCOUNTRY=$HOSTCOUNTRY INFRADOMAIN=$INFRADOMAIN splk_routing_map=\"$ROUTING_MAP_VERSION\" status=ok"

                                      else
                                              _logme "func=_getDeploymentServer msg=\"cannot find valid DS in $ROUTING_MAP\" HOSTCOUNTRY=$HOSTCOUNTRY INFRADOMAIN=$INFRADOMAIN splk_routing_map=\"$ROUTING_MAP_VERSION\" status=ko"
                                      fi
                               fi
                       else
                               _logme "func=_getDeploymentServer msg=\"one of LDAP parameters missing\" HOSTCOUNTRY=$HOSTCOUNTRY INFRADOMAIN=$INFRADOMAIN status=ko"
                       fi
               fi
               rm $FILE 2>/dev/null
        else
               _logme "func=_getDeploymentServer msg=\"unable to create temp file using mktemp\" status=ko"
        fi
}

# set DS using parameters. $1 is targetUri, $2 is clientName.
_setDeploymentServer() {
        DIR=`dirname $DEPLOYMENTCLIENT_CONF`
        if [ ! -x "$DIR" ]; then
               _logme "func=_setDeploymentServer msg=\"unable to create deploymentclient.conf. Directory does not exist.\" file=\"$DEPLOYMENTCLIENT_CONF\" dir=\"$(pwd)\" status=ko"
               exit 1
        fi
        umask 0022
cat <<EOF > $DEPLOYMENTCLIENT_CONF
[deployment-client]
clientName = $2
[target-broker:deploymentServer]
targetUri = $1
EOF
        if [ $? -eq 0 ]; then
               _logme "func=_setDeploymentServer msg=\"done\" ds=\"$1\" client_name="$2" deploymentclientconf=\"`pwd`/$DEPLOYMENTCLIENT_CONF\" status=ok"
        else
               _logme "func=_setDeploymentServer msg=\"write error to deploymentclient.conf\" ds=\"$1\" client_name=\"$2\" deploymentclientconf=\"$DEPLOYMENTCLIENT_CONF\" status=ko"
        fi
}

_prolog() {
        _queryCmd ldapsearch
        LDAPSEARCH="ldapsearch"

        LDAPSEARCH_LINUX="$LDAPSEARCH -x -LLL -h $LDAP_HOST:$LDAP_PORT -b $LDAP_BASEDN $LDAP_INPUT_PARAM $LDAP_OUTPUT_PARAM"
        LDAPSEARCH_SOLARIS="$LDAPSEARCH -L -h $LDAP_HOST -p $LDAP_PORT -b $LDAP_BASEDN $LDAP_INPUT_PARAM $LDAP_OUTPUT_PARAM"
        LDAPSEARCH_AIX="$LDAPSEARCH -L -h $LDAP_HOST:$LDAP_PORT -b $LDAP_BASEDN $LDAP_INPUT_PARAM $LDAP_OUTPUT_PARAM"

        case "x$ARCH" in
               "xAIX")
                       LDAPSEARCH_CMD=$LDAPSEARCH_AIX
                       ;;
               "xSolaris|xSunOS")
                       LDAPSEARCH_CMD=$LDAPSEARCH_SOLARIS
                       ;;
               *)
                       LDAPSEARCH_CMD=$LDAPSEARCH_LINUX
                       ;;
        esac

        _queryCmd mktemp
        MKTEMP="mktemp"

        _queryCmd cut
        CUT="cut"
}

_verify() {
        _prolog
        _getDeploymentServer
        [ ! -f $DEPLOYMENTCLIENT_CONF ] && _usage && exit 1
        CLIENT_NAME="`hostname`_$INFRADOMAIN-$HOSTCOUNTRY"
        grep clientName $DEPLOYMENTCLIENT_CONF | grep $CLIENT_NAME
        if [ $? -eq 0 ]; then
               _logme "func=_verify msg=\"LDAP data and deploymentclient.conf match\" deploymentclientconf=\"$DEPLOYMENTCLIENT_CONF\" status=ok"
        else
               _logme "func=_verify msg=\"LDAP data does not match with deploymentclient.conf match\" deploymentclientconf=\"$DEPLOYMENTCLIENT_CONF\" status=ko"
        fi

}

_usage() {
        echo "usage: $0 method [params]"
        echo "methods:"
        echo "  configure [pathToDeploymentClientConf]"
        echo "  override [hostname|ipaddress] [pathToDeploymentClientConf]"
        echo "  testDeploymentServer [hostname|ipaddress tcpport]"
        echo "  verify [pathToDeploymentClientConf]"
        echo

}

[ $# -lt 1 ] && _usage && exit 1
ARCH=`uname -s`
HOSTNAME="hostname"

case "x$1" in
        "xconfigure")
               [ $# -gt 1 ] && DEPLOYMENTCLIENT_CONF=$2
               if [ -s $OVERRIDE_FILE ]; then
                       SPLK_DEST_DS=$(cat $OVERRIDE_FILE)
                       CLIENT_NAME="`hostname`_override"
                       _logme "func=override msg=\"using DS from $OVERRIDE_FILE\" ds=\"$SPLK_DEST_DS\" status=ok"
               else
                       _prolog
                       _getDeploymentServer
                       CLIENT_NAME="`hostname`_$INFRADOMAIN-$HOSTCOUNTRY"
               fi
               _setDeploymentServer "$SPLK_DEST_DS" "$CLIENT_NAME"
               ;;
        "xoverride")
               [ $# -lt 2 ] && _usage && exit 1
                SPLK_DEST_DS=$2
               [ $# -gt 2 ] && DEPLOYMENTCLIENT_CONF=$3
               CLIENT_NAME="`hostname`_override"
               _logme "func=override msg=\"using DS from override\" ds=\"$SPLK_DEST_DS\" status=ok"
               _setDeploymentServer "$SPLK_DEST_DS" "$CLIENT_NAME"
               echo $2 > $OVERRIDE_FILE
               ;;
        "xverify")
               [ $# -gt 1 ] && DEPLOYMENTCLIENT_CONF=$2
               _verify
               ;;
        "xtestDeploymentServer")
               [ $# -lt 3 ] && _usage && exit 1
               _testDeploymentServer $2 $3
               ;;
        *)
               _usage
               exit 1
esac
