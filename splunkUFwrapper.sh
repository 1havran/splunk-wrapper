#!/bin/sh
#
# SecIT, Vladimir Had
# 1. run LDAPSEARCH against LDAP_INPUT_PARAM and output values in LDAP_OUTPUT_PARAM
# 2. LDAP_OUTPUT_PARAM is statically extracted to separate variables as arrays in BASH are not supported by all shells
# 3. Values from LDAP_OUTPUT_PARAM are greped against ROUTING_MAP to find defined destination
#
# splk_routing_map.cfg structure:
# version:n
# param1,param2,destination
#
# the version should be manually increased when doing updates to the routing map to track the issues

LDAP_HOST="ldap.compute.internal"
LDAP_HOST="localhost"
LDAP_PORT="389"
LDAP_BASEDN="dc=eu-west-2,dc=compute,dc=internal"
LDAP_INPUT_PARAM="(uid=wlutz)"
LDAP_OUTPUT_PARAM="uidNumber gidNumber"
ROUTING_MAP="splk_routing_map.cfg"
USE_STDOUT=1
#USE_LOGGER=$(which logger)

logme() {
	if [ $USE_STDOUT ]; then
		echo "script=$0 timestamp=\"$(date)\" hostname=$($HOSTNAME) $@"
	fi
	if [ $USE_LOGGER ]; then
		$USE_LOGGER "script=$0 timestamp=\"$(date)\" hostname=$($HOSTNAME) $@"
	fi
}

getDeploymentServer() {
	FILE=$($MKTEMP)
	if [ $FILE ]; then
		$LDAPSEARCH_CMD > $FILE
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
					DS_OK=1
				else
					logme "func=getDeploymentServer msg=\"cannot find valid DS in $ROUTING_MAP\" HOSTCOUNTRY=$HOSTCOUNTRY INFRADOMAIN=$INFRADOMAIN splk_routing_map=\"$ROUTING_MAP_VERSION\" status=ko"
				fi
			fi
		else
			logme "func=getDeploymentServer msg=\"one of LDAP parameters missing\" HOSTCOUNTRY=$HOSTCOUNTRY INFRADOMAIN=$INFRADOMAIN status=ko"
		fi
		rm $FILE 2>/dev/null
	else
		logme "func=getDeploymentServer msg=\"unable to create temp file using mktemp\" status=ko"
	fi
}

setDeploymentServer() {
	logme "func=setDeploymentServer msg=\"not defined yet\""
}

prolog() {
	UNAME=$(which uname)
	HOSTNAME=$(which hostname)
	LDAPSEARCH=$(which ldapsearch)
	if [ $? != 0 ]; then
		logme "func=prolog msg=\"cannot locate ldapsearch using which\" status=ko"
		exit 1
	fi
	LDAPSEARCH_LINUX="$LDAPSEARCH -x -LLL -h $LDAP_HOST:$LDAP_PORT -b $LDAP_BASEDN $LDAP_INPUT_PARAM $LDAP_OUTPUT_PARAM"
	LDAPSEARCH_SOLARIS=""
	LDAPSEARCH_AIX=""
	LDAPSEARCH_CMD=$LDAPSEARCH_LINUX
	
	MKTEMP=$(which mktemp)
	if [ $? != 0 ]; then
		logme "func=prolog msg=\"cannot locate mktemp using which\" status=ko"
		exit 1
	fi
	
	CUT=$(which cut)
	if [ $? != 0 ]; then
		logme "func=prolog msg=\"cannot locate cut using which\" status=ko"
		exit 1
	fi
	logme "func=prolog msg=\"found: cut ldapsearch mktemp\" status=ok"
}
	
prolog
getDeploymentServer #returns DS_OK=1 if DS is foudn
if [ $DS_OK ]; then
	setDeploymentServer
fi

