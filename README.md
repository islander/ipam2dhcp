# IPAM2DHCP

Script for generating isc-dhcp-server `include` sections for your subnets using [phpIPAM](https://github.com/phpipam/phpipam) database.

## Configuration

Put `my.cnf` credentials in directory with script:

```
$ cat my.cnf
[client]
user=phpipam
password=phpipampasswd
```

Other configuration in script's vars section:

```
$ vim subnet2dhcp.sh

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

```

## Usage

```
$ mysql phpipam
mysql> select id, description, inet_ntoa(subnet), mask from subnets where description rlike 'homenet'\G
*************************** 1. row ***************************
               id: 9
      description: homenet
inet_ntoa(subnet): 192.0.2.0
             mask: 24
1 row in set (0.00 sec)

mysql> SELECT inet_ntoa(ip_addr), hostname, mac FROM ipaddresses WHERE ip_addr!='0' AND subnetId=9;
+--------------------+-----------+-------------------+
| inet_ntoa(ip_addr) | hostname  | mac               |
+--------------------+-----------+-------------------+
| 192.0.2.20         | hostname1 | 02:00:49:2a:fe:72 |
| 192.0.2.21         | hostname2 | 02:00:36:2a:fe:a6 |
| 192.0.2.22         | hostname3 | 02:00:6d:4b:15:1f |
+--------------------+-----------+-------------------+
3 rows in set (0.00 sec)

$ cat /etc/dhcp/dhcpd.conf
subnet 192.0.2.0 netmask 255.255.255.0 {
        range 192.0.2.20 192.0.2.30;
        option routers 192.0.2.1;

        # auto-generated config
        include "/etc/dhcp/conf.d/homenet.conf";
}

$ sudo ./subnet2dhcp.sh homenet
Generation homenet.conf...
saving old config to homenet.conf~2019-06-24T15:29:45+11:00...
Found: 3 devices

Done. Verify changes:

host hostname1 { hardware ethernet 02:00:49:2a:fe:72 ; fixed-address 192.0.2.20 ; }
host hostname2 { hardware ethernet 02:00:36:2a:fe:a6 ; fixed-address 192.0.2.21 ; }
host hostname3 { hardware ethernet 02:00:6d:4b:15:1f ; fixed-address 192.0.2.22 ; }

restart isc-dhcp-server? [y/N] n

$ cat /etc/dhcp/conf.d/homenet.conf
host hostname1 { hardware ethernet 02:00:49:2a:fe:72 ; fixed-address 192.0.2.20 ; }
host hostname2 { hardware ethernet 02:00:36:2a:fe:a6 ; fixed-address 192.0.2.21 ; }
host hostname3 { hardware ethernet 02:00:6d:4b:15:1f ; fixed-address 192.0.2.22 ; }
```
