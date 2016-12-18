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

LDAP_HOST="ldap.compute.internal"
LDAP_HOST="localhost"
LDAP_PORT="389"
LDAP_BASEDN="dc=eu-west-2,dc=compute,dc=internal"
LDAP_INPUT_PARAM="(uid=wlutz)"
LDAP_OUTPUT_PARAM="uidNumber gidNumber"

ROUTING_MAP="./splk_routing_map.conf"
OVERRIDE_FILE="./splk_override.conf"
#DEPLOYMENTCLIENT_CONF="/opt/splunkforwarder/etc/system/default/deploymentclient.conf"
DEPLOYMENTCLIENT_CONF="./deploymentclient.conf"

USE_STDOUT=1
#USE_LOGGER=1

logme() {
	if [ $USE_STDOUT ]; then
		echo "script=$0 arch=$ARCH timestamp=\"$(date)\" hostname=$($HOSTNAME) $@"
	fi
	if [ $USE_LOGGER ]; then
		LOGGER="logger"
		$LOGGER "script=$0 arch=$ARCH timestamp=\"$(date)\" hostname=$($HOSTNAME) $@"
	fi
}

# do not depend on which(1) - from Splunk TA nix
queryCmd() {
	for dir in `echo $PATH | sed 's/:/ /g'`; do
		if [ -x $dir/$1 ]; then
			return 0
		fi
	done
	logme "func=prolog msg=\"Mandatory command not found" cmd=\"$1\" path=\"$PATH\"" status=ko"
	exit 1
}


getDeploymentServer() {
	FILE=$($MKTEMP)
	if [ $FILE ]; then
		$LDAPSEARCH_CMD > $FILE
		LDAP_ERROR_CODE=$?
		if [ $LDAP_ERROR_CODE -gt 0 ]; then
			logme "func=getDeploymentServer ldaperror=$LDAP_ERROR_CODE msg=\"cannot connect to LDAP\" ldapsearch=\"$LDAPSEARCH_CMD\" status=ko"
		else
			#dont use bash array as it is not supported by old shells
			HOSTCOUNTRY=$(grep uidNumber $FILE | $CUT -d' ' -f2-)
			INFRADOMAIN=$(grep gidNumber $FILE | $CUT -d' ' -f2-)
			if [ $HOSTCOUNTRY ] && [ $INFRADOMAIN ]; then
				if [ ! -f $ROUTING_MAP ]; then
					logme "func=getDeploymentServer msg=\"cannot locate $ROUTING_MAP\" dir=$(pwd) status=ko"
				else
					ROUTING_MAP_VERSION=$(grep version $ROUTING_MAP 2>/dev/null)
					$(grep -q "^$HOSTCOUNTRY,$INFRADOMAIN" $ROUTING_MAP 2>/dev/null)
					if [ $? = 0 ]; then
						#uniq in case there are duplicates
						SPLK_DEST_DS=$(grep "^$HOSTCOUNTRY,$INFRADOMAIN" $ROUTING_MAP | $CUT -d, -f3 | sort | uniq | head -n 1)

						logme "func=getDeploymentServer msg=\"DS found\" ds=$SPLK_DEST_DS HOSTCOUNTRY=$HOSTCOUNTRY INFRADOMAIN=$INFRADOMAIN splk_routing_map=\"$ROUTING_MAP_VERSION\" status=ok"

					else
						logme "func=getDeploymentServer msg=\"cannot find valid DS in $ROUTING_MAP\" HOSTCOUNTRY=$HOSTCOUNTRY INFRADOMAIN=$INFRADOMAIN splk_routing_map=\"$ROUTING_MAP_VERSION\" status=ko"
					fi
				fi
			else
				logme "func=getDeploymentServer msg=\"one of LDAP parameters missing\" HOSTCOUNTRY=$HOSTCOUNTRY INFRADOMAIN=$INFRADOMAIN status=ko"
			fi
		fi
		rm $FILE 2>/dev/null
	else
		logme "func=getDeploymentServer msg=\"unable to create temp file using mktemp\" status=ko"
	fi
}

setDeploymentServer() {
	if [ ! -f $DEPLOYMENTCLIENT_CONF ]; then
		logme "func=setDeploymentServer msg=\"unable to locate deploymentclient config\" file=\"$DEPLOYMENTCLIENT_CONF\" dir=\"$(pwd)\" status=ko"
		exit 1
	fi
	queryCmd sed
	SED="sed"
	$SED -i.orig -e "s/DEFAULTVALUE/$1/g" $DEPLOYMENTCLIENT_CONF	
	logme "func=setDeploymentServer msg=\"done\" ds=\"$1\" status=ok"
}

prolog() {
	ARCH=`uname -s`

	queryCmd ldapsearch
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
	
	queryCmd mktemp
	MKTEMP="mktemp"
	
	queryCmd cut
	CUT="cut"
}

HOSTNAME="hostname"
#if override file exists, read the content (one line) and use it as splk destination ds
if [ -s $OVERRIDE_FILE ]; then
	SPLK_DEST_DS=$(cat $OVERRIDE_FILE)
	logme "func=override msg=\"using DS from override file\" ds=\"$SPLK_DEST_DS\" status=ok"
else
	prolog
	getDeploymentServer
fi

if [ "$SPLK_DEST_DS" ] ; then
	setDeploymentServer "$SPLK_DEST_DS"
	return 0
fi

return 1
