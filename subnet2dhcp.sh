#!/bin/bash
# vim: tabstop=4 shiftwidth=4 softtabstop=4 textwidth=120 expandtab :

###########################################################
#  Generate isc-dhcp-server config from phpIPAM database  #
#
#  Modified: 2019-06-24
#  (c)https://github/islander/ipam2dhcp                   #
###########################################################


######################
#  bash strict mode  #
######################

set -euo pipefail
#set -x  # uncomment for debug output

#####################
#  Yes/No function  #
#####################

confirm()
{
    read -n 1 -r -p "${1}? [y/N] "
    if [[ $REPLY =~ ^[Yy]$ ]]; then
            echo ""
            return 0;
    else
            echo ""
            return 1;
    fi
}

#################
#  Validate IP  #
#################

function valid_ip()
{
    local  ip=$1
    local  stat=1

    if [[ $ip =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
        OIFS=$IFS
        IFS='.'
        ip=($ip)
        IFS=$OIFS
        [[ ${ip[0]} -le 255 && ${ip[1]} -le 255 \
            && ${ip[2]} -le 255 && ${ip[3]} -le 255 ]]
        stat=$?
    fi
    return $stat
}

###############
#  Variables  #
###############

SCRIPT_PATH="$(dirname $0)"
BACKUP_PATH="/var/backups/dhcpd"
DBNAME="phpipam"
DBHOST="localhost"
SUBNET="${1:-homenet}"
SUBNET_CONF="/etc/dhcp/conf.d/${SUBNET}.conf"
MYSQL_OPTS="--defaults-file=${SCRIPT_PATH}/my.cnf -h ${DBHOST} -BNrs"

SUBNET_ID="$(echo "SELECT id FROM subnets WHERE description RLIKE '^${SUBNET}' LIMIT 1;" | mysql $MYSQL_OPTS "$DBNAME")"
if [[ "${SUBNET_ID}" == "" ]]; then
    echo "FATAL: network not found."
    exit 1
fi

SQL="SELECT mac, inet_ntoa(ip_addr) as ipaddr, CONCAT('', hostname) as hostname \
     FROM ipaddresses \
     WHERE ip_addr!='0' AND mac RLIKE '^([0-9A-Fa-f]{2}[:-]){5}([0-9A-Fa-f]{2})$' AND subnetId='${SUBNET_ID}';"

mapfile DEVICES < <(echo "$SQL" | mysql $MYSQL_OPTS "$DBNAME")  # populate devices array

echo "Generation ${SUBNET_CONF}..."

# backup existed config
if [[ -f "${SUBNET_CONF}" ]]; then
    mkdir -p "$BACKUP_PATH"
    NOW="$(date --iso-8601=seconds)"
    echo "saving old config to ${BACKUP_PATH}/${SUBNET_CONF}~${NOW}..."
    mv "${SUBNET_CONF}" "${BACKUP_PATH}/${SUBNET_CONF}~${NOW}"
fi

CNT=${#DEVICES[@]}
echo "Found: $CNT devices"

if [[ $CNT -le 0 ]]; then
    echo "FATAL: Devices not found."
    exit 1
fi

# disable globbing and set separator
set -f; IFS=$'\n' 
for LINE in ${DEVICES[@]}; do
    IFS=$'\t' read -r MA IP HN <<< "$LINE"

    if ! valid_ip "$IP"; then
        echo "ERROR: Incorrect IP: $IP. Skipping."
        continue
    fi

    if [[ ! "$MA" =~ ^([a-fA-F0-9]{2}:){5}[a-fA-F0-9]{2}$ ]]; then
        echo "ERROR: Incorrect MAC: $MA. Skipping."
        continue
    fi

    if [[ "$(expr length "$HN")" > 0 ]]; then
        echo "host ${HN,,} { hardware ethernet ${MA,,} ; fixed-address $IP ; }" >> $SUBNET_CONF
    else
        echo "WARNING: Empty hostname for ${IP}. Using MAC."
        HN="${MA//[":"]}"
        echo "host host-${HN,,} { hardware ethernet ${MA,,} ; fixed-address $IP ; }" >> $SUBNET_CONF
    fi
done

# restore globbing and separator
unset IFS ; set +f

echo ""
echo "Done. Verify changes:"
echo ""
cat $SUBNET_CONF
echo ""

confirm "restart isc-dhcp-server" && (echo "restarting."; service isc-dhcp-server restart)
