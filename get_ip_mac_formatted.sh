#!/bin/bash
get_eth_interfaces() {
  # Execute the command and capture the output
  local interfaces=$(ip a | grep BROAD | grep eth | awk '{print $2}' | tr -d ':')

  # Print the extracted Ethernet interfaces
  echo "$interfaces"
}

print_eth_info() {
  local eth_int="$1"
  local ip_output=$(ip a)

  # Print headers
  printf "%-15s %-20s %-17s\n" "Interface" "IP Address" "MAC Address"
  echo "---------------------------------------------------"

  # Iterate through the list of Ethernet interfaces
  for iface in $eth_int; do
    # Use grep and awk to extract IP and MAC addresses for each interface
    ip_address=$(ifconfig $iface | grep inet | grep broad | awk '{print $2}')
    mac_address=$(ifconfig $iface | grep ether | awk '{print $2}')

    # Print the information with formatting
    printf "%-15s %-20s %-17s\n" "$iface" "$ip_address" "$mac_address"
  done
}

# Call the function to get Ethernet interfaces
eth_interfaces=$(get_eth_interfaces)

# Call the function with the eth_interfaces variable
print_eth_info "$eth_interfaces"
