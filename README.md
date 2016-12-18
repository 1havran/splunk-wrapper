Wrapper for Splunk UF

Description: splunkUFwrapper reads the specific data from LDAP and replaces the
 value in deploymentclient.conf based on the routing map.

	deploymentclient.conf	splunk UF configuration file with value to 
				REPLACE
	splk_override.conf	override parameter for replacement value
	splk_routing_map.conf	routing map to select final destination based 
				on the input from LDAP
	splunkUFwrapper.sh	the wrapper itself

Files:
	deploymentclient.conf
	- configuration file for Splunk UF
	- targetUri contains the value to be replaced by the wrapper
	- to apply the changes Splunk UF needs to be restarted. 
		It is not managed by the wrapper

	splk_override.conf
	- this file contains only one line with the hostname or 
		IP address of target deployment server

	splunkUFwrapper.sh
	- the wrapper runs following functions in the order:
		1. override check
		2. prolog
		3. getDeploymentServer
		4. setDeploymentServer
	- the errors are logged to STDOUT using logme function

	- 1. if override file exists, 2) and 3) are skipped and the 
		wrapper executes 4) directly. the override value is 
		read from the file (first line), stored in $SPLK_DEST_DS
		and passed to 4)
	- 2. prolog function checks for mandatory functions within $PATH
		variable. which(1) is not used as it might not exist in 
		various UNIX systems.
		* cut, ldapsearch, mktemp
	- 3. getDeploymentServer is using ldapsearch to get the parameters
		from LDAP. Intermediate results are stored in temporary 
		file using mktemp. The variables are extracted from temp 
		file and found in splk_routing_map.conf. Routing map has 
		simple structure: first line contains version of file 
		(version:1), all other lines have following structure: 
		A,B,C. The parameters A,B are extracted from LDAP. Entire 
		line is grepped using A,B and C as a destination is returned 
		using cut. C is stored in SPLK_DEST_DS.
	- 4. setDeploymentServer replaces the value 
		in deploymentclient.conf by SPLK_DEST_DS.

