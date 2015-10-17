#!/bin/bash
#
#  This code parses /proc/net/dev and does some math on the result to give me various iface statistics.
#  The line I care about looks like either:
#     eth11:    1264       5    0    0    0     0          0         2     4692      50    0    0    0     0       0          0
# or  eth11:12341264       5    0    0    0     0          0         2     4692      50    0    0    0     0       0          0
#  So I want to grab the line in question (based on interface name) and replace the colon with a space so the parsing will look the same

export TK_USE_CURRENT_LOCALE=1
export LC_NUMERIC=en_US
ethtool_iface_file="/tmp/.ethtool_iface_file"
proc_iface_file="/tmp/.proc_iface_file"

SILENT=" >/dev/null 2>&1"

trap ctrl_c INT


function ctrl_c() {
    echo "** Trapped CTRL-C"
    /bin/rm -f ${ethtool_iface_file} ${proc_iface_file}
    pkill super-pps.sh
    pkill -9 super-pps.sh
}


function usage () {
errcode=$1
case $errcode in
    2)
    ;;
    3) echo -en "\nError: at least -p or -e must be specified.\n"
    ;;
    4) echo -en "\nError: interval must be an integer superior than 0.\n"
    ;;
    *) errcode=1
    ;;
esac

echo "
Usage: super-pps.sh [-hept] [-d list-of-interfaces] [-i interval-in-seconds]
Monitor network interfaces

  -h, --help                 Give this help list
  -e, --ethtool              Shows \"ethetool -S\" statistics    - at least e or p should be specified
  -p, --procnetdev           Shows \"/proc/net/dev\" statistics  - at least e or p should be specified
  -t, --total                Shows the total of all devices cumulated
  -d, --devicelist           Uses the interfaces separated by comas, e.g. \"-d eth0,eth1\"
  -i, --interval             Monitoring interval in seconds (value > 0)
  -c, --cpu                  Displays CPU usage (in SAR)

Mandatory or optional arguments to long options are also mandatory or optional
for any corresponding short options.
"
exit $errcode
}

function cpu_stats {
echo -en "\nCPU Statistics:\n"
sar -P ALL 1 1 | grep -Ev "100.00$| 9[7-9].[0-9][0-9]$" | grep Average
}

function show() {
    #/proc/net/dev - eth0       5,427,452      65       5,401,472      65           2,865           2,851   
    #/proc/net/dev - eth1       5,413,728      65       5,435,130      65           2,858           2,869   
    # Displays the stats file and the total of throughput and averages the packet size
    sf=$1
    type=$(awk '{print $1}' $1)
    total="total"
    rx_pps=$(awk '{gsub(/,/,"",$4) ; t=t+$4} END{print t}' $1) ; tx_pps=$(awk '{gsub(/,/,"",$6) ; t=t+$6} END{print t}' $1)
    rx_mbps=$(awk '{gsub(/,/,"",$8) ; t=t+$4} END{print t}' $1) ; tx_mbps=$(awk '{gsub(/,/,"",$9) ; t=t+$4} END{print t}' $1)
    rs_packet_size=$(awk '{gsub(/,/,"",$4) ; aps=aps+($4*$5) ; t=t+$4} END{print aps/t}' $1)
    printf "$format" "/proc/net/dev - ${iface}" ${proc_rx_pps} ${proc_rx_pack_size} ${proc_tx_pps} ${proc_tx_pack_size} ${proc_rx_bps} ${proc_tx_bps} "" >> ${proc_iface_file}
}


#########################################################################################################
# read the options
TEMP=`getopt -o a::eptchd:i: --long arga::,ethtool,procnetdev,total,cpu,help,devicelist:interval: -n 'test.sh' -- "$@"`
eval set -- "$TEMP"

# extract options and their arguments into variables.
while true ; do
    case "$1" in
        -e|--ethtool) ARG_E=1 ; shift ;;
        -p|--procnetdev) ARG_P=1 ; shift ;;
        -t|--total) ARG_T=1 ; shift ;;
        -c|--cpu) ARG_C=1 ; shift ;;
        -h|--help) usage ; shift ;;
        -d|--devicelist)
            case "$2" in
                "") shift 2 ;;
                *) devicelist=$2 ; shift 2 ;;
            esac ;;
        -i|--interval)
            case "$2" in
                "") shift 2 ;;
                *) interval=$2 ; shift 2 ;;
            esac ;;
        --) shift ; break ;;
        *) echo "Internal error!" ; exit 1 ;;
    esac
done

# do something with the variables -- in this case the lamest possible one :-)
#echo "ARG_A = $ARG_A"
#echo "List of devices to monitor = $devicelist"
#echo "Interval in seconds = $interval"
#echo "Show Ethtool stats (1=yes, 0=no) = $ARG_E"
#echo "Show /proc/net/dev stats (1=yes, 0=no) = $ARG_P"
#########################################################################################################

# Checking argument validity
if [[ $ARG_E != "1" ]] && [[ $ARG_P != "1" ]] ; then usage 3 ; fi
if [[ $interval -le 0 ]] ; then usage 4; fi

echo $devicelist | sed "s/,/\n/g" | while read iface; do
    if [[ $ARG_P == "1" ]] ; then
        interface_in_devprocnet=$(grep ${iface}: /proc/net/dev | sed s/:/\ / )
        # Bail if we don't find output...
        if [ -z "${interface_in_devprocnet}" ]; then
           echo "Count not find interface: ${iface} in /proc/net/dev!"
           exit 1
        fi
    elif [[ $ARG_E == "1" ]] ; then
        interface_in_ethtool=$(ethtool -S ${iface}) >/dev/null 2>&1
        # Bail if we don't find output...
        if [ $? -ne 0 ] && [ -z "${interface_in_ethtool}" ]; then
           echo "Count not retrieve stats from ethtool for interface: ${iface} !"
           exit 1
        fi       
    fi
done

# We enter the infinite loop
while true ; do
    :> ${proc_iface_file}
    :> ${ethtool_iface_file}
    format="%24s%16s%8s%16s%8s%16s%16s   %-s\n"
    printf "$format" "________________________" "________________" "________" "________________" "________" "________________" "________________" ""
    printf "$format" "NIC" "Rx PPS" "RxSiz" "Tx PPS" "TxSiz" "Rx MBps" "Tx MBps" " "
    printf "$format" "-----------------------" "---------------" "-------" "---------------" "-------" "---------------" "---------------" ""

    echo $devicelist | sed "s/,/\n/g" | while read iface; do
        proc1_f=/tmp/.proc.${iface}.1
        proc2_f=/tmp/.proc.${iface}.2 
        ethtool1_f=/tmp/.ethtool-S.${iface}.1
        ethtool2_f=/tmp/.ethtool-S.${iface}.2

        grep ${iface} /proc/net/dev > ${proc1_f}
        ethtool -S ${iface} > ${ethtool1_f} 2> /dev/null
        sleep $interval
        grep ${iface} /proc/net/dev > ${proc2_f}
        ethtool -S ${iface} > ${ethtool2_f} 2> /dev/null

    done

    echo $devicelist | sed "s/,/\n/g" | while read iface; do
        proc1_f=/tmp/.proc.${iface}.1
        proc2_f=/tmp/.proc.${iface}.2 
        ethtool1_f=/tmp/.ethtool-S.${iface}.1
        ethtool2_f=/tmp/.ethtool-S.${iface}.2

        if [[ $ARG_E == "1" ]] ; then
            # Ethtool
            ethtool_rx_bps=$(paste ${ethtool1_f} ${ethtool2_f} | grep rx_bytes_nic: |sed 's/rx_bytes_nic://g' | awk -v interval=$interval '{Bps=((8*($2-$1)/interval)/10^6)} END{printf("%d\n",Bps)}')
            ethtool_tx_bps=$(paste ${ethtool1_f} ${ethtool2_f} | grep tx_bytes_nic: |sed 's/tx_bytes_nic://g' | awk -v interval=$interval '{Bps=((8*($2-$1)/interval)/10^6)} END{printf("%d\n",Bps)}')
            ethtool_rx_pps=$(paste ${ethtool1_f} ${ethtool2_f} | grep rx_pkts_nic: |sed 's/rx_pkts_nic://g' | awk -v interval=$interval '{pps=($2-$1)/interval} END{printf("%d\n",pps)}')
            ethtool_tx_pps=$(paste ${ethtool1_f} ${ethtool2_f} | grep tx_pkts_nic: |sed 's/tx_pkts_nic://g' | awk -v interval=$interval '{pps=($2-$1)/interval} END{printf("%d\n",pps)}')
            if (( ethtool_rx_pps == 0 )) ; then ethtool_rx_pack_size=0 ; else ethtool_rx_pack_size=$(echo $ethtool_rx_bps*10^6/8/$ethtool_rx_pps|bc); fi
            if (( ethtool_tx_pps == 0 )) ; then ethtool_tx_pack_size=0 ; else ethtool_tx_pack_size=$(echo $ethtool_tx_bps*10^6/8/$ethtool_tx_pps|bc); fi
            # reformat numbers with thousand separators
            ethtool_rx_pps=$(printf "%'d\n" $ethtool_rx_pps) ; ethtool_rx_pack_size=$(printf "%'.f\n" ${ethtool_rx_pack_size}) ; ethtool_tx_pps=$(printf "%'d\n" $ethtool_tx_pps)
            ethtool_tx_pack_size=$(printf "%'.f\n" ${ethtool_tx_pack_size}) ; ethtool_rx_bps=$(printf "%'d\n" $ethtool_rx_bps) ; ethtool_tx_bps=$(printf "%'d\n" $ethtool_tx_bps)
            printf "$format" "ethtool - ${iface}" ${ethtool_rx_pps} ${ethtool_rx_pack_size} ${ethtool_tx_pps} ${ethtool_tx_pack_size} ${ethtool_rx_bps} ${ethtool_tx_bps} "" >> ${ethtool_iface_file}
        fi

        if [[ $ARG_P == "1" ]] ; then
            # PROC
            proc_rx_bps=$(paste ${proc1_f} ${proc2_f} | awk -v interval=$interval '{Bps=((8*($19-$2)/interval)/10^6)}  END{printf("%d\n",Bps)}')
            proc_tx_bps=$(paste ${proc1_f} ${proc2_f} | awk -v interval=$interval '{Bps=((8*($27-$10)/interval)/10^6)} END{printf("%d\n",Bps)}')
            proc_rx_pps=$(paste ${proc1_f} ${proc2_f} | awk -v interval=$interval '{Pps=($20-$3)/interval}  END{printf("%d\n",Pps)}')
            proc_tx_pps=$(paste ${proc1_f} ${proc2_f} | awk -v interval=$interval '{Pps=($28-$11)/interval} END{printf("%d\n",Pps)}')
            if (( proc_rx_pps == 0 )) ; then proc_rx_pack_size=0 ; else proc_rx_pack_size=$(echo $proc_rx_bps*10^6/8/$proc_rx_pps|bc); fi
            if (( proc_tx_pps == 0 )) ; then proc_tx_pack_size=0 ; else proc_tx_pack_size=$(echo $proc_tx_bps*10^6/8/$proc_tx_pps|bc); fi
            # reformat numbers with thousand separators
            proc_rx_pps=$(printf "%'.f\n" ${proc_rx_pps}) ; proc_rx_pack_size=$(printf "%'.f\n" ${proc_rx_pack_size}) ; proc_tx_pps=$(printf "%'.f\n" ${proc_tx_pps})
            proc_tx_pack_size=$(printf "%'.f\n" ${proc_tx_pack_size}) ; proc_rx_bps=$(printf "%'.f\n" ${proc_rx_bps}) ; proc_tx_bps=$(printf "%'.f\n" ${proc_tx_bps})
            printf "$format" "/proc/net/dev - ${iface}" ${proc_rx_pps} ${proc_rx_pack_size} ${proc_tx_pps} ${proc_tx_pack_size} ${proc_rx_bps} ${proc_tx_bps} "" >> ${proc_iface_file}
        fi
    done
    if [[ $ARG_E == "1" ]] ; then cat ${ethtool_iface_file} ; fi
    if [[ $ARG_P == "1" ]] ; then cat ${proc_iface_file} ; fi
    if [[ $ARG_C == "1" ]] ; then  cpu_stats ; fi
done

