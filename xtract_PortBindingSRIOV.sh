## script_name: xtract_PortBindingSRIOV.sh 
## A simple bash script to get the neutron port information given the compute hostname. The flow of information extraction is below: 
#   1. Extract the unique switchports that the compute uses on the switch side from nuage-switchport-mapping-list
#   2. Extract the neutron port list from the unique switchport
#   3. Extract the binding information from the neutron port-list
# This script will work on Openstack with Nuage Support Neutron drivers 

source overcloudrc 
sriov_compute=$1
## This command extracts the unique switchports that the compute uses on the wbx side. Assumption is that each compute is connected to two switch ports: 

unique_swp=$(neutron nuage-switchport-mapping-list |grep -i $sriov_compute | awk '{ print $6 }'|sort | uniq)
swp_port1=$(echo $unique_swp | cut -d' ' -f1)
swp_port2=$(echo $unique_swp | cut -d' ' -f2)
#swp_port3=$(echo $unique_swp | cut -d' ' -f3)
#swp_port4=$(echo $unique_swp | cut -d' ' -f4)

## extracting neutron port list from the switch port 
neutron_port_list1=$(neutron nuage-switchport-binding-list|grep $swp_port1|awk '{ print $4 }')
neutron_port_list2=$(neutron nuage-switchport-binding-list|grep $swp_port2|awk '{ print $4 }')
#neutron_port_list3=$(neutron nuage-switchport-binding-list|grep $swp_port3|awk '{ print $4 }')
#neutron_port_list4=$(neutron nuage-switchport-binding-list|grep $swp_port4|awk '{ print $4 }')

## extracting binding information from neutron_port_list1 
echo -e "PORT_NAME \t BINDING_PROFILE \t BINDING_VIF_DETAILS \t BINDING_VIF_TYPE \t BINDING_VNIC_TYPE \t PORT_STATUS \t IP_ADDRESS \t MAC_ADDR"
for neutron_port in $neutron_port_list1 ; do hostname=$(neutron port-show $neutron_port | grep binding:host_id|awk '{ print $4 }'); port_name=$(neutron port-show $neutron_port | grep name | awk '{ print $4 }'); binding_profile=$(neutron port-show $neutron_port | grep binding:profile|awk '{ print substr($0, index($0,$4)) }'); binding_vif_details=$(neutron port-show $neutron_port | grep binding:vif_details|awk '{ print substr($0, index($0,$4)) }'); binding_vif_type=$(neutron port-show $neutron_port | grep binding:vif_type|awk '{ print substr($0, index($0,$4)) }'); binding_vnic_type=$(neutron port-show $neutron_port | grep binding:vnic_type|awk '{ print substr($0, index($0,$4)) }'); port_status=$(neutron port-show $neutron_port | grep status|awk '{ print substr($0, index($0,$4)) }') ; ip_addr=$(neutron port-show $neutron_port|grep fixed_ips |awk '{print $7}'|awk '{gsub(/\"|\;/,"")}1'| sed 's/.$//') ; mac_addr=$(neutron port-show $neutron_port|grep mac|awk '{print $4}'); echo -e "$port_name \t $hostname \t $binding_profile \t $binding_vif_details \t $binding_vif_type \t $binding_vnic_type \t $port_status \t $ip_addr \t $mac_addr "; done 

## extracting binding information from neutron_port_list2
for neutron_port in $neutron_port_list2 ; do hostname=$(neutron port-show $neutron_port | grep binding:host_id|awk '{ print $4 }'); port_name=$(neutron port-show $neutron_port | grep name | awk '{ print $4 }'); binding_profile=$(neutron port-show $neutron_port | grep binding:profile|awk '{ print substr($0, index($0,$4)) }'); binding_vif_details=$(neutron port-show $neutron_port | grep binding:vif_details|awk '{ print substr($0, index($0,$4)) }'); binding_vif_type=$(neutron port-show $neutron_port | grep binding:vif_type|awk '{ print substr($0, index($0,$4)) }'); binding_vnic_type=$(neutron port-show $neutron_port | grep binding:vnic_type|awk '{ print substr($0, index($0,$4)) }'); port_status=$(neutron port-show $neutron_port | grep status|awk '{ print substr($0, index($0,$4)) }') ; ip_addr=$(neutron port-show $neutron_port|grep fixed_ips |awk '{print $7}'|awk '{gsub(/\"|\;/,"")}1'| sed 's/.$//') ; mac_addr=$(neutron port-show $neutron_port|grep mac|awk '{print $4}'); echo -e "$port_name \t $hostname \t $binding_profile \t $binding_vif_details \t $binding_vif_type \t $binding_vnic_type \t $port_status \t $ip_addr \t $mac_addr "; done 

## extracting binding information from neutron_port_list3
#for neutron_port in $neutron_port_list3 ; do hostname=$(neutron port-show $neutron_port | grep binding:host_id|awk '{ print $4 }'); port_name=$(neutron port-show $neutron_port | grep name | awk '{ print $4 }'); binding_profile=$(neutron port-show $neutron_port | grep binding:profile|awk '{ print substr($0, index($0,$4)) }'); binding_vif_details=$(neutron port-show $neutron_port | grep binding:vif_details|awk '{ print substr($0, index($0,$4)) }'); binding_vif_type=$(neutron port-show $neutron_port | grep binding:vif_type|awk '{ print substr($0, index($0,$4)) }'); binding_vnic_type=$(neutron port-show $neutron_port | grep binding:vnic_type|awk '{ print substr($0, index($0,$4)) }'); port_status=$(neutron port-show $neutron_port | grep status|awk '{ print substr($0, index($0,$4)) }') ; echo -e "$port_name \t $hostname \t $binding_profile \t $binding_vif_details \t $binding_vif_type \t $binding_vnic_type \t $port_status " ; done

## extracting binding information from neutron_port_list4
#for neutron_port in $neutron_port_list4 ; do hostname=$(neutron port-show $neutron_port | grep binding:host_id|awk '{ print $4 }'); port_name=$(neutron port-show $neutron_port | grep name | awk '{ print $4 }'); binding_profile=$(neutron port-show $neutron_port | grep binding:profile|awk '{ print substr($0, index($0,$4)) }'); binding_vif_details=$(neutron port-show $neutron_port | grep binding:vif_details|awk '{ print substr($0, index($0,$4)) }'); binding_vif_type=$(neutron port-show $neutron_port | grep binding:vif_type|awk '{ print substr($0, index($0,$4)) }'); binding_vnic_type=$(neutron port-show $neutron_port | grep binding:vnic_type|awk '{ print substr($0, index($0,$4)) }'); port_status=$(neutron port-show $neutron_port | grep status|awk '{ print substr($0, index($0,$4)) }') ; echo -e "$port_name \t $hostname \t $binding_profile \t $binding_vif_details \t $binding_vif_type \t $binding_vnic_type \t $port_status " ; done
