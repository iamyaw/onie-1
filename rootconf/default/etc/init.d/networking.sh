#!/bin/sh

PATH=/usr/bin:/usr/sbin:/bin:/sbin

. /lib/onie/functions

import_cmdline

# Static ethernet management configuration
config_ethmgmt_static()
{
    if [ -n "$onie_ip" ] ; then
        # ip= was set on the kernel command line and configured by the
        # kernel already.  Do no more.
        log_console_msg "Using static IP config: ip=$onie_ip"
        return 0
    fi

    return 1
}

# DHCPv6 ethernet management configuration
config_ethmgmt_dhcp6()
{
    intf=$1
    shift

    # TODO
    # log_info_msg "TODO: Checking for DHCPv6 ethmgmt configuration."

    return 1
}

# DHCPv4 ethernet management configuration
config_ethmgmt_dhcp4()
{
    intf=$1
    shift

    # no default args
    udhcp_args="$(udhcpc_args) -n -o"
    if [ "$1" = "discover" ] ; then
        udhcp_args="$udhcp_args -t 5 -T 3"
    else
        udhcp_args="$udhcp_args -t 15 -T 3"
    fi
    udhcp_request_opts=
    for o in subnet broadcast router domain hostname ntpsrv dns logsrv search ; do
        udhcp_request_opts="$udhcp_request_opts -O $o"
    done

    log_info_msg "Trying DHCPv4 on interface: $intf"
    tmp=$(udhcpc $udhcp_args $udhcp_request_opts $udhcp_user_class -i $intf -s /lib/onie/udhcp4_net)
    if [ "$?" = "0" ] ; then
        local ipaddr=$(ifconfig $intf |grep 'inet '|sed -e 's/:/ /g'|awk '{ print $3 " / " $7 }')
        log_console_msg "Using DHCPv4 addr: ${intf}: $ipaddr"
    else
        _log_err_msg "DHCPv4 on interface: $intf failed"
        return 1
    fi
    return 0

}

# Fall back ethernet management configuration
config_ethmgmt_fallback()
{

    local base_ip=10
    local default_nm="255.255.255.0"
    local default_hn="onie-host"
    intf_counter=$1
    shift
    intf=$1
    shift

    interface_base_ip=$(( $base_ip + $intf_counter ))
    # Assign sequential static IP to each detected interface
    local default_ip="192.168.3.$interface_base_ip"
    log_console_msg "Using default IPv4 addr: ${intf}: ${default_ip}/${default_nm}"
    ifconfig $intf $default_ip netmask $default_nm || {
        _log_err_msg "Problems setting default IPv4 addr: ${intf}: ${default_ip}/${default_nm}"
        return 1
    }

    hostname $default_hn || {
        _log_err_msg "Problems setting default hostname: ${intf}: ${default_hn}"
        return 1
    }

    return 0

}

# Configure the management interface
# Try these methods in order:
# 1. static, from kernel command line parameters
# 2. DHCPv6
# 3. DHCPv4
# 4. Fall back to well known IP address
config_ethmgmt()
{
    intf_list=$(net_intf)
    intf_counter=0
    return_value=0

    config_ethmgmt_static "$*" && return

    # Bring up all the interfaces for the subsequent methods.
    for intf in $intf_list ; do
        cmd_run ifconfig $intf up
        params="$intf $*"
        eval "result_${intf}=0"
        config_ethmgmt_dhcp6 $params  || config_ethmgmt_dhcp4 $params || config_ethmgmt_fallback $intf_counter $params || eval "result_${intf}=1"
        intf_counter=$(( $intf_counter + 1))
    done
    for intf in $intf_list ; do
        eval "curr_intf_result=\${result_${intf}}"
        if [ "x$curr_intf_result" != "x0" ] ; then
            log_console_msg "Failed to configure ${intf} interface"
            return_value=1
        fi
    done
    return $return_value
}

config_ethmgmt "$*"
