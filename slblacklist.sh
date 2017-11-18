#!/bin/bash
##
## /usr/local/script/slblacklist.sh
## Download and set ip-ranges to block using ipset
##
## Created on 18 NOV 2017
##
## Arguments:
##  -i: initialise iptables and ipset 
##	-d: download ip addresses from ipdeny.com 
##	-s: set blacklist for downloaded ip addresses
##	-l: list blacklist details
##	-h: displays usage
##

# Define functions
function checktocontinue {
	# Ask to continue
	read -p "Continue (y/n)? " -n 1 -r
	if [[ "$REPLY" =~ ^[Yy]$ ]]; then
		printf "\n"
	else
		printf "\nYou choose not to continue. Exiting.\n"
		exit ${ERRORCODE}
	fi
}

function printhelp {
	printf -- "Usage: %s -i | -d | -s | [-h] \n" ${0##*/}
	printf -- "  -i : initialise iptables and ipset blacklist (required only once) \n"
	printf -- "  -d : download ip network ranges from %s \n" ${ZONEURL}
	printf -- "  -s : set blacklist for downloaded ip addresses \n"
	printf -- "  -l : list blacklist details\n"
	printf -- "  -h : show this help message \n"
	printf -- "The ip ranges should be in cidr format and stored in %s.\n" ${IPFILE}
}

# Set variables and do not use unset variables
set -u

ZONES="cn ru"
ZONEURL="http://www.ipdeny.com/ipblocks/data/countries"
IPFILE="/srv/etc/zones/blacklist"
BLACKLIST="slblacklist"
BLACKLISTSWAP="${BLACKLIST}-swap"

# Check if this script is run as root, ipset is installed and if options; otherwise exit.
if [[ $(whoami) != root ]]; then
	printf "Must be root to execute this script. Exiting.\n"
	exit 1
fi

if [[ ! -x $(which ipset) ]]; then
	printf -- "Package ipset seems not to be installed. Exiting.\n" ${IPFILE}
	exit 1
fi


# Check if no options
if [[ ! $@ =~ ^\-.+ ]]; then
	printhelp
	exit 2
fi

# Evaluate options
while getopts "idslh" opt; do
	case "$opt" in
		\? | h)
			printhelp
			exit 2
			;;
		i)
			printf -- "Initialising blacklist... \n"
			# Create blaclist
			ipset create ${BLACKLIST} hash:net hashsize 4096
			ipset create ${BLACKLISTSWAP} hash:net hashsize 4096
			# Initialise ip tables
			iptables -I INPUT -m set --match-set ${BLACKLIST} src -j DROP
			iptables -I FORWARD -m set --match-set ${BLACKLIST} src -j DROP
			;;
		d)
			# Get ip ranges from web lists and save to file
			printf  -- "Downloading zones... "
			echo "## $(date)" > ${IPFILE}
			echo "## Zones: ${ZONES}" >> ${IPFILE}
			for zone in ${ZONES}; do
				printf -- "%s " ${zone}
				echo "# Network address ranges for ${zone} zone" >> ${IPFILE}
				wget -q ${ZONEURL}/${zone}.zone -O - >> ${IPFILE}
  			done
			printf -- "done.\n Saved ip ranges to: %s\n" ${IPFILE}
			;;
		s)
			# Check if file with ip ranges exists
			if [[ ! -e ${IPFILE} ]]; then
				printf -- "File with ip ranges does not exist: %s. Exiting.\n" ${IPFILE}
				exit 1
			fi

			# Empty swap list and reset counter
			ipset flush ${BLACKLISTSWAP}
			cnt=0

			# Get ip ranges from file one by one and add to blacklist
			printf -- "Adding ip address ranges from %s to swap list... " ${IPFILE}
			while read iprange; do
				cnt=$((cnt+1))
				# Check for comment lines
				if [[ ! ${iprange} =~ ^#+ ]]; then
					ipset -exist add ${BLACKLISTSWAP} ${iprange}
				fi
			done < ${IPFILE}
			printf -- "added %s entries.\n" ${cnt}
			
			# Swap ip lists
			printf -- "Ready to swap %s with %s... " ${BLACKLIST} ${BLACKLISTSWAP}
			checktocontinue
			ipset swap ${BLACKLIST} ${BLACKLISTSWAP}
			;;
		l)
			# List blacklists
			printf -- "## Main ip adress ranges blacklist: \n"
			ipset list ${BLACKLIST} -terse
			printf -- "\n## Swap list: \n"
			ipset list ${BLACKLISTSWAP} -terse
			printf -- "\n"
			;;
		:)
			printf -- "Option -%s requires an argument. Exiting." "${OPTARG}"
			exit 1
			;;
	esac
done

# Done
printf "All done.\n"
exit 0
