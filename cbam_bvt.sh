#!/bin/bash
# CBAM BVT - Bundled Version - Generated: 2026-01-16 18:30:08 GMTST
# Authors: tiago.reis.ext@nokia.com & joao.1.martins@nokia.com


COLORIZE_OUTPUT="${COLORIZE_OUTPUT:-false}"
COLOR_GREEN='\033[0;32m'
COLOR_RED='\033[0;31m'
COLOR_NC='\033[0m'

print_status() {
    local status="$1"
    local message="$2"
    local prefix="${3:-}"
    if [[ "${COLORIZE_OUTPUT}" == "true" ]]; then
        if [[ "${status}" == "OK" ]]; then
            printf "\n${prefix} ${COLOR_GREEN}✓ OK${COLOR_NC}  || ${message}\n"
        else
            printf "\n${prefix} ${COLOR_RED}✗ FAILED${COLOR_NC} || ${message}\n"
        fi
    else
        if [[ "${status}" == "OK" ]]; then
            printf "\n${prefix} ✓ OK  || ${message}\n"
        else
            printf "\n${prefix} ✗ FAILED || ${message}\n"
        fi
    fi
}

print_check_result() {
    local status="$1"
    local message="${2:-}"
    if [[ "${COLORIZE_OUTPUT}" == "true" ]]; then
        if [[ "${status}" == "OK" ]]; then
            printf "${COLOR_GREEN}✓ OK${COLOR_NC}"
        else
            printf "${COLOR_RED}✗ FAILED${COLOR_NC}"
        fi
    else
        if [[ "${status}" == "OK" ]]; then
            printf "✓ OK"
        else
            printf "✗ FAILED"
        fi
    fi
    if [[ -n "${message}" ]]; then
        printf " - ${message}"
    fi
    printf "\n"
}

print_section_header() {
    local check_name="$1"
    local host="${2:-}"
    local separator="########################################"

    printf "\n%s\n" "${separator}"
    if [[ -n "${host}" ]]; then
        printf "[%s] - %s\n" "${host}" "${check_name}"
    else
        printf "%s\n" "${check_name}"
    fi
    printf "%s\n\n" "${separator}"
}

validate_cbam_system() {
    local errors=0

    printf "\n=== Pre-flight System Validation ===\n\n"

    printf "Checking for ectl utility... "
    if ! command -v ectl &> /dev/null; then
        print_check_result "FAILED"
        printf "  ERROR: 'ectl' command not found. This does not appear to be a CBAM system.\n"
        errors=$((errors + 1))
    else
        print_check_result "OK"
    fi

    printf "Checking for cbam utility... "
    if ! command -v cbam &> /dev/null && [ ! -f "/usr/bin/cbam" ]; then
        print_check_result "FAILED"
        printf "  ERROR: 'cbam' command not found. This does not appear to be a CBAM system.\n"
        errors=$((errors + 1))
    else
        print_check_result "OK"
    fi

    printf "Checking for cbam-status utility... "
    if [ ! -f "/opt/nokia/cbam/bin/cbam-status" ]; then
        print_check_result "FAILED"
        printf "  ERROR: 'cbam-status' not found at /opt/nokia/cbam/bin/cbam-status\n"
        errors=$((errors + 1))
    else
        print_check_result "OK"
    fi

    printf "Checking etcd connectivity... "
    if ! sudo ectl ls /cbam &> /dev/null; then
        print_check_result "FAILED"
        printf "  ERROR: Cannot access etcd. Check if etcd service is running.\n"
        errors=$((errors + 1))
    else
        print_check_result "OK"
    fi

    printf "Checking for CBAM cluster configuration... "
    local cbam_size=$(sudo ectl get cbam/cluster/cbamsize 2>/dev/null)
    local cluster_name=$(sudo ectl get cbam/cluster/clustername 2>/dev/null)

    if [ -z "${cbam_size}" ] && [ -z "${cluster_name}" ]; then
        print_check_result "FAILED"
        printf "  ERROR: CBAM-specific etcd parameters not found.\n"
        printf "  This system does not appear to have CBAM cluster configuration.\n"
        errors=$((errors + 1))
    else
        print_check_result "OK"
        if [ -n "${cbam_size}" ]; then
            printf "  CBAM Size: ${cbam_size}\n"
        fi
        if [ -n "${cluster_name}" ]; then
            printf "  Cluster Name: ${cluster_name}\n"
        fi
    fi

    printf "Checking for required system tools... "
    local missing_tools=()

    for tool in fio iostat jq curl grep awk sed ssh; do
        if ! command -v ${tool} &> /dev/null; then
            missing_tools+=("${tool}")
        fi
    done

    if [ ${#missing_tools[@]} -gt 0 ]; then
        printf "⚠ WARNING\n"
        printf "  Missing tools: ${missing_tools[*]}\n"
        printf "  Some BVT checks may not work properly.\n"
    else
        print_check_result "OK"
    fi

    printf "\n"

    if [ ${errors} -gt 0 ]; then
        printf "=== VALIDATION FAILED ===\n"
        printf "\n⚠️  This does not appear to be a valid CBAM system.\n\n"
        printf "Possible reasons:\n"
        printf "  • Not running on a CBAM node\n"
        printf "  • CBAM services not installed\n"
        printf "  • etcd service not running\n"
        printf "  • Missing CBAM cluster configuration\n\n"
        printf "Please ensure you are running this script on a CBAM app node.\n\n"
        return 1
    else
        printf "=== VALIDATION PASSED ===\n"
        printf "System validated as a CBAM node.\n"
        printf "Proceeding with BVT checks...\n\n"
        return 0
    fi
}

validate_ha_active_node() {
    local arch=$(sudo ectl ls /cbam/nodes 2>/dev/null | wc -l)

    if [[ ${arch} -eq 1 ]]; then
        return 0
    fi

    printf "\n=== HA Node Validation ===\n\n"
    printf "Checking if running on active APP node...\n"

    if systemctl is-active --quiet cps.service 2>/dev/null; then
        print_check_result "OK" "cps.service is active on this node"
        printf "This is the active APP node. Continuing...\n\n"
        return 0
    else
        print_check_result "FAILED" "cps.service is not active on this node"
        printf "\n"
        printf "⚠️  For HA deployments, this script must be run on the active APP node.\n\n"
        printf "The active APP node is identified by:\n"
        printf "  • cps.service is active and running\n"
        printf "  • Usually the node handling active CBAM operations\n\n"
        printf "Please identify the active APP node and run the script there.\n\n"
        printf "To check which node has active cps service:\n"
        printf "  sudo systemctl status cps.service\n\n"
        return 1
    fi
}

list_backups_on_sftp() {
    local sftp_key="/home/backup/sftp_server_private_key.pem"
    local username=$(sudo ectl get /cbam/cluster/components/backup/sftp/connection/username 2>/dev/null)
    local password=$(sudo ectl get /cbam/cluster/components/backup/sftp/connection/password 2>/dev/null)
    local hostname=$(sudo ectl get /cbam/cluster/components/backup/sftp/connection/hostname 2>/dev/null)
    local root_dir=$(sudo ectl get /cbam/cluster/components/backup/sftp/root_dir 2>/dev/null)
    local cluster_name=$(sudo ectl get cbam/cluster/clustername 2>/dev/null)
    local ip_length=$(echo ${hostname} | wc -c)

    export SSHPASS=${password}

    if [ -n "${password}" ]; then
        if [[ "${ip_length}" -gt 15 ]]; then
            sshpass -e sftp -oBatchMode=no -oStrictHostKeyChecking=no -b - ${username}@[${hostname}] <<EOF
cd ${root_dir}
ls -latrh ${cluster_name}*
EOF
        else
            sshpass -e sftp -oBatchMode=no -oStrictHostKeyChecking=no -b - ${username}@${hostname} <<EOF
cd ${root_dir}
ls -latrh ${cluster_name}*
EOF
        fi
    else
        if [[ "${ip_length}" -gt 15 ]]; then
            sudo sftp -i ${sftp_key} -oBatchMode=no -oStrictHostKeyChecking=no -b - ${username}@[${hostname}] <<EOF
cd ${root_dir}
ls -latrh ${cluster_name}*
bye
EOF
        else
            sudo sftp -i ${sftp_key} -oBatchMode=no -oStrictHostKeyChecking=no -b - ${username}@${hostname} <<EOF
cd ${root_dir}
ls -latrh ${cluster_name}*
bye
EOF
        fi
    fi
}

list_georedundancy_files() {
    local sftp_key=$(sudo ectl get /cbam/cluster/components/geo_redundancy/sftp/connection/private_key 2>/dev/null)
    local username=$(sudo ectl get /cbam/cluster/components/geo_redundancy/sftp/connection/username 2>/dev/null)
    local password=$(sudo ectl get /cbam/cluster/components/geo_redundancy/sftp/connection/password 2>/dev/null)
    local hostname=$(sudo ectl get /cbam/cluster/components/geo_redundancy/sftp/connection/hostname 2>/dev/null)
    local root_dir=$(sudo ectl get /cbam/cluster/components/geo_redundancy/sftp/root_dir 2>/dev/null)
    local imported_id=$(sudo ectl get /cbam/cluster/components/geo_redundancy/imported_instance_id 2>/dev/null)
    local ip_length=$(echo ${hostname} | wc -c)

    export SSHPASS=${password}

    if [ -n "${password}" ]; then
        if [[ "${ip_length}" -gt 15 ]]; then
            sshpass -e sftp -oBatchMode=no -oStrictHostKeyChecking=no -b - ${username}@[${hostname}] <<EOF
cd ${root_dir}
ls -latrh ${imported_id}*
ls -latrh *.heartbeat
EOF
        else
            sshpass -e sftp -oBatchMode=no -oStrictHostKeyChecking=no -b - ${username}@${hostname} <<EOF
cd ${root_dir}
ls -latrh ${imported_id}*
ls -latrh *.heartbeat
EOF
        fi
    else
        if [[ "${ip_length}" -gt 15 ]]; then
            sudo sftp -i ${sftp_key} -oBatchMode=no -oStrictHostKeyChecking=no -b - ${username}@[${hostname}] <<EOF
cd ${root_dir}
ls -latrh ${imported_id}*
ls -latrh *.heartbeat
bye
EOF
        else
            sudo sftp -i ${sftp_key} -oBatchMode=no -oStrictHostKeyChecking=no -b - ${username}@${hostname} <<EOF
cd ${root_dir}
ls -latrh ${imported_id}*
ls -latrh *.heartbeat
bye
EOF
        fi
    fi
}

display_active_alarms() {
    print_section_header "Active Alarms"

    local data=$(curl -s http://localhost:8082/api/alma/alarms | jq '[.[] | select(.clearedAt == null) | {id: .id, clearedAt: .clearedAt, severity: .severity, createdAt: .createdAt, lastSourceEventTime: .lastSourceEventTime, text: .text}]')

    printf "%-10s | %-10s | %-24s | %-30s\n" "ID" "Severity" "Created At" "Description"
    printf "%-10s-+-%-10s-+-%-20s-+-%-30s\n" "----------" "----------" "------------------------" "--------------------------------------------------------------------------------------------------"

    echo "${data}" | jq -c '.[]' | while read -r row; do
        local id=$(echo "${row}" | jq -r '.id')
        local severity=$(echo "${row}" | jq -r '.severity')
        local created_at=$(echo "${row}" | jq -r '.createdAt')
        local text=$(echo "${row}" | jq -r '.text')

        printf "%-10s | %-10s | %-20s | %-30s\n" "${id}" "${severity}" "${created_at}" "${text}"
        printf "%-10s-+-%-10s-+-%-20s-+-%-30s\n" "----------" "----------" "------------------------" "--------------------------------------------------------------------------------------------------"
    done
}

check_network_configuration() {
    local vip_nic=$(sudo ectl ls cbam/cluster/system/network_interfaces 2>/dev/null)
    vip_nic="${vip_nic:0:1}"

    print_section_header "Network Configuration"
    printf "Listing cluster public IP addresses...\n"
    grep -v '^#\|.*dock\|^127\|^:\|.*end' /etc/hosts | sort -u -k2 | awk '!a[$1]++' | awk '!($3="")' | awk '{t=$1; $1=$2; $2=t; print;}'

    if [ -n "${vip_nic}" ]; then
        printf "\nListing cluster VIP addresses...\n\n"
        sudo etool export cbam/cluster/system/network_interfaces 2>/dev/null | grep -e if -e cidr | awk '{gsub("{","");gsub("\"","");gsub(" ","");gsub("cidr:",""); print}'
    else
        printf "\nThis system doesn't have VIPs configured.\n\n"
    fi

    printf "\nChecking network zones configuration in ETCD...\n\n"
    sudo ectl ls /cbam/cluster/system/network_zones --recursive -p 2>/dev/null | grep -v '/$' | xargs -n 1 -I% sh -c "echo -n %:; sudo ectl get %;" | sort | grep -i "interface"

    if [ -n "${vip_nic}" ]; then
        printf "\nChecking VIP network interface configuration in ETCD...\n\n"
        sudo ectl ls /cbam/cluster/system/network_interfaces --recursive -p 2>/dev/null | grep -v '/$' | xargs -n 1 -I% sh -c "echo -n %:; sudo ectl get %;" | sort
    fi

    printf "\nChecking individual node network interface configuration in ETCD...\n\n"
    sudo ectl ls /cbam/nodes/ --recursive -p 2>/dev/null | grep -v '/$' | xargs -n 1 -I% sh -c "echo -n %:; sudo ectl get %;" | sort | grep -i "network_interfaces"

    printf "\nListing cluster DNS IP addresses...\n\n"
    sudo ectl ls /cbam/nodes/ --recursive -p 2>/dev/null | grep -v '/$' | xargs -n 1 -I% sh -c "echo -n %:; sudo ectl get %;" | sort | grep -i "dns"

    printf "\nGrabbing configured NTP server details...\n"
    ectl ls /cbam/nodes/ --recursive -p 2>/dev/null | grep -v '/$' | xargs -n 1 -I% sh -c "echo -n %:; sudo ectl get %;" | sort | grep -i "ntp"
    echo -e "\n"
}

check_snmp_configuration() {
    print_section_header "SNMP Configuration"
    sudo ectl ls /cbam/cluster/components/omagent/snmp_adaptation/ --recursive -p 2>/dev/null | grep -v '/$' | xargs -n 1 -I% sh -c "echo -n %:; sudo ectl get %;"
    echo -e "\n"
}

check_cbam_size() {
    print_section_header "CBAM Size Configuration"

    local cbam_size=$(sudo ectl get cbam/cluster/cbamsize 2>/dev/null)

    if [ -n "${cbam_size}" ]; then
        if [ "${cbam_size}" == "S" ]; then
            printf "This CBAM size was set to S...\n\nSetting this CBAM size to M...\n\n ### WARNING ###\n ###This configuration will only be active on the next cbam-reconfigure process...###\n"
            sudo ectl set cbam/cluster/cbamsize "M" 1>/dev/null
        else
            printf "This CBAM size is already set to ${cbam_size}, no change required...\n"
        fi
    else
        printf "CBAM size parameter does not exist on this system.\n"
    fi
}

check_backup_configuration() {
    print_section_header "Backup Configuration"

    local cbam_log_dir="/var/log/cbam"
    local merge_logs=$(sudo ectl get cbam/cluster/components/syslog/merge_all_cbam_logs 2>/dev/null)
    local backup_enabled=$(sudo ectl get /cbam/cluster/components/backup/backup_enabled 2>/dev/null)
    local backup_schedule_count=$(sudo ectl ls /cbam/cluster/components/backup/full_schedule/ 2>/dev/null | wc -l)
    local grub_password=$(sudo ectl get cbam/cluster/security/hardening/grub_password 2>/dev/null)
    local grub_user=$(sudo cat /etc/grub.d/01_users 2>/dev/null | awk -F= 'NR==6{print $2}')

    local full_backups=$(grep "Full backup finished" ${cbam_log_dir}/backup.log ${cbam_log_dir}/backup.log.1 2>/dev/null | wc -l)

    printf "Checking backup.log and backup.log.1 for full backup...\n\n"

    if [[ ${full_backups} -gt 0 ]]; then
        grep "Full backup finished" ${cbam_log_dir}/backup.log ${cbam_log_dir}/backup.log.1 2>/dev/null
        print_status "OK" "Found ${full_backups} backups"
    else
        print_status "FAILED" "No fullbackup found on the logs...!"
    fi

    printf "\nChecking backup configuration...\n"
    if [ -n "${backup_enabled}" ]; then
        if [ "${backup_enabled}" == "true" ]; then
            print_status "OK" "Full Backup is enabled with the following settings..."
            sudo ectl ls /cbam/cluster/components/backup/sftp/ --recursive -p 2>/dev/null | grep -v '/$' | xargs -n 1 -I% sh -c "echo -n %:; sudo ectl get %;"
            printf "\nListing backups available on sftp server...\n"
            list_backups_on_sftp
        else
            print_status "FAILED" "Full Backup is not Enabled..."
        fi
    else
        printf "\nParameter backup_enable doesn't exist on this system. Printing available backup config...\n"
        printf "\n\nectl verifications for SFTP...\n\n"
        sudo ectl ls /cbam/cluster/components/backup/sftp/ --recursive -p 2>/dev/null | grep -v '/$' | xargs -n 1 -I% sh -c "echo -n %:; sudo ectl get %;"
    fi

    if [ ${backup_schedule_count} -gt 0 ]; then
        printf "\nectl verifications for BACKUP_SCHEDULE...\n\n"
        sudo ectl ls /cbam/cluster/components/backup/full_schedule/ --recursive -p 2>/dev/null | grep -v '/$' | xargs -n 1 -I% sh -c "echo -n %:; sudo ectl get %;"
    else
        print_status "FAILED" "FULL_SCHEDULE config doesn't exist on this system..."
    fi

    if [ -n "${grub_password}" ]; then
        printf "\nThe GRUB password for user '${grub_user}' is: $(sudo ectl get cbam/cluster/security/hardening/grub_password)\n"
        echo -e "\n"
    else
        printf "\nThere is no GRUB password defined on this system...\n"
    fi

    if [ -n "${merge_logs}" ]; then
        if [ "${merge_logs}" == "false" ]; then
            printf "\nMerge logs is disabled, so no \"all.log\" will be listed\n"
        else
            printf "\nMerge logs is enabled, so \"all.log\" will be listed\n"
            ls -latrh ${cbam_log_dir}/all* 2>/dev/null
        fi
    else
        printf "\nListing /var/log/cbam/all*...\n"
        ls -latrh ${cbam_log_dir}/all* 2>/dev/null
    fi
}

check_georedundancy() {
    print_section_header "Geo-Redundancy Configuration"

    local geo_enabled=$(sudo ectl get /cbam/cluster/georedundancy/georedundant 2>/dev/null)
    local cbam_version=$(cbam -V 2>/dev/null | awk 'NR==1{print substr($3,0,2)}')

    if [ -n "${geo_enabled}" ]; then
        if [ "${geo_enabled}" == "true" ]; then
            local geo_cluster=""

            if [ "${cbam_version}" -gt 21 ]; then
                geo_cluster=$(sudo ectl get cbam/cluster/components/geo_redundancy/imported_instance_id 2>/dev/null)
                printf "\nGeoredundancy is enabled on this CBAM with the following settings...\n"
                sudo ectl ls cbam/cluster/components/geo_redundancy/ --recursive -p 2>/dev/null | grep -v '/$' | xargs -n 1 -I% sh -c "echo -n %:; sudo ectl get %;"
            else
                geo_cluster=$(sudo ectl get cbam/cluster/components/backup_importer/imported_instance_id 2>/dev/null)
                printf "\nGeoredundancy is enabled on this CBAM with the following settings...\n"
                sudo ectl ls /cbam/cluster/components/backup_importer/ --recursive -p 2>/dev/null | grep -v '/$' | xargs -n 1 -I% sh -c "echo -n %:; sudo ectl get %;"
            fi

            echo -e "\n"
            sudo ectl ls /cbam/cluster/georedundancy/ --recursive -p 2>/dev/null | grep -v '/$' | xargs -n 1 -I% sh -c "echo -n %:; sudo ectl get %;"
            echo -e "\n"

            printf "\nChecking georedundancy status...\n"
            sudo /opt/nokia/cbam/bin/georedundancy-cli status

            printf "\nListing files available on the configured GeoR folder...\n"
            list_georedundancy_files

            echo -e "\n"
            printf "\nThis CBAM is georedundant with CBAM '${geo_cluster}', please run the BVT script also on this cluster and verify the configuration...\n"
        else
            printf "\nThis CBAM has no Georedundancy configured...\n"
            printf "\nListing Managed VNFS...\n"
            sudo /opt/nokia/cbam/bin/georedundancy-cli list-vnfs managed 2>/dev/null
            echo -e "\n"
        fi
    else
        printf "\nThis CBAM version doesn't allow georedundancy...\n\n"
    fi
}

DEDUP_LOGS="${DEDUP_LOGS:-true}"

deduplicate_messages() {
    awk '
    function normalize(line) {
        gsub(/[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}(\.[0-9]+)?(Z|[+-][0-9]{2}:[0-9]{2})?/, "", line)
        gsub(/(Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec) [0-9]{1,2} [0-9]{2}:[0-9]{2}:[0-9]{2}/, "", line)
        gsub(/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/, "UUID", line)
        gsub(/0x[0-9a-fA-F]+/, "HEX", line)
        gsub(/[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+/, "IP", line)
        gsub(/:[0-9]+/, ":PORT", line)
        gsub(/[0-9]{3,}/, "NUM", line)
        gsub(/[ \t]+/, " ", line)
        return line
    }

    function extract_vnf(line) {
        if (match(line, /CBAM-[a-zA-Z0-9]{32}/)) {
            return substr(line, RSTART, RLENGTH)
        }
        return "NO_VNF"
    }

    {
        vnf = extract_vnf($0)
        norm = normalize($0)
        key = vnf "|||" norm

        if (!(key in counts)) {
            counts[key] = 0
            first_line[key] = $0
            order[++total] = key
        }
        counts[key]++
    }

    END {
        for (i = 1; i <= total; i++) {
            key = order[i]
            count = counts[key]
            line = first_line[key]
            if (count > 1) {
                printf "> [%dx] --- %s\n", count, line
            } else {
                print line
            }
        }
    }
    '
}

check_logs() {
    local log_file="$1"
    local log_basename=$(basename "${log_file}")

    print_section_header "Log Analysis: ${log_basename}"

    local error_count=$(sudo grep -e 'ERROR ' -e '|ERROR|' "${log_file}" 2>/dev/null | wc -l)
    local critical_count=$(sudo grep -e 'CRITICAL ' -e '|CRITICAL|' "${log_file}" 2>/dev/null | wc -l)

    if [[ "${DEDUP_LOGS}" == "true" ]]; then
        sudo grep -e 'ERROR ' -e '|ERROR|' -e 'CRITICAL ' -e '|CRITICAL|' "${log_file}" 2>/dev/null | deduplicate_messages
    else
        sudo grep -e 'ERROR ' -e '|ERROR|' -e 'CRITICAL ' -e '|CRITICAL|' "${log_file}" 2>/dev/null | sort
    fi

    if [[ ${error_count} -eq 0 ]]; then
        print_status "OK" "no ERRORS found"
    else
        print_status "FAILED" "${error_count} ERROR found please check"
    fi

    if [[ ${critical_count} -eq 0 ]]; then
        print_status "OK" "no CRITICAL found"
    else
        print_status "FAILED" "${critical_count} CRITICAL found please check"
    fi

}

check_all_logs_in_directory() {
    local log_dir="$1"
    local exclude_pattern="${2:-vnf\|alma\|workflows\|grow_cluster\|watson}"

    if [[ -d "${log_dir}" ]]; then
        for log_file in $(ls ${log_dir}/*.log 2>/dev/null | grep -v "${exclude_pattern}"); do
            check_logs "${log_file}"
        done
    else
        printf "Folder ${log_dir} does not exist, so no logs will be checked on this folder\n"
    fi
}

check_app_node_resources() {
    local cpus=$(nproc)
    local arch=$(sudo ectl ls /cbam/nodes 2>/dev/null | wc -l)
    local hostname_short=$(hostname -s)
    local host="[${hostname_short}] "

    if [[ ${arch} -eq 1 ]]; then
        host=""
        hostname_short=""
    fi

    local mem=$(free -m | awk 'NR==2{print $2}')
    local app_mem_required=30000
    local disk=$(sudo pvs 2>/dev/null | awk 'NR==2{print $5}' | cut -c1-4 | tr -d "<")
    local disk_int=$(printf "%.0f\n" ${disk})

    print_section_header "APP Node Resources" "${hostname_short}"

    printf "${host}Number of CPUs: ${cpus}\n"
    if [[ "${cpus}" -lt 8 ]]; then
        print_status "FAILED" "Required CPUs is 8"
    else
        print_status "OK" "Required CPUs achieved"
        echo -e "\n"
    fi

    printf "${host}Memory Summary (${mem}M)\n"
    if (( "${mem} < ${app_mem_required}" )); then
        print_status "FAILED" "Required memory is 32000M"
        echo -e "\n"
    else
        print_status "OK" "Required memory achieved"
        echo -e "\n"
    fi

    printf "\n${host}Disk Size: ${disk_int}Gb\n"
    if [[ "${disk_int}" -lt 300 ]]; then
        print_status "FAILED" "Disk size (${disk_int}Gb) is not compliant... required amount is 300Gb"
    else
        print_status "OK" "Disk size requirement achieved ${disk_int}GB..."
        echo -e "\n"
    fi

    echo -e "\n"
}

check_db_node_resources() {
    local cpus=$(nproc)
    local arch=$(sudo ectl ls /cbam/nodes 2>/dev/null | wc -l)
    local hostname_short=$(hostname -s)
    local host="[${hostname_short}] "

    if [[ ${arch} -eq 1 ]]; then
        host=""
        hostname_short=""
    fi

    local mem=$(free -m | awk 'NR==2{print $2}')
    local db_mem_required=7729
    local disk=$(sudo pvs 2>/dev/null | awk 'NR==2{print $5}' | cut -c1-4 | tr -d "<")
    local disk_int=$(printf "%.0f\n" ${disk})

    print_section_header "DB Node Resources" "${hostname_short}"

    printf "${host}Number of CPUs: ${cpus}\n"
    if [[ "${cpus}" -lt 4 ]]; then
        print_status "FAILED" "Required CPUs is 4"
    else
        print_status "OK" "Required CPUs achieved"
    fi

    printf "${host}Memory Summary (${mem}M)\n"
    if (( "${mem} < ${db_mem_required}" )); then
        print_status "FAILED" "Required memory is 7729M"
        echo -e "\n"
    else
        print_status "OK" "Required memory achieved"
        echo -e "\n"
    fi

    printf "\n${host}Disk Size: ${disk_int}Gb\n"
    if [[ "${disk_int}" -lt 300 ]]; then
        print_status "FAILED" "Disk size (${disk_int}Gb) is not compliant... required amount is 300Gb"
    else
        print_status "OK" "Disk size requirement achieved (${disk_int}Gb).."
        echo -e "\n"
    fi

    echo -e "\n"
}

check_single_node_resources() {
    local cpus=$(nproc)
    local mem=$(free -m | awk 'NR==2{print $2}')
    local disk=$(sudo pvs 2>/dev/null | awk 'NR==2{gsub("<",""); printf "%.0f\n", $5}')
    local total_mem_required=30000

    print_section_header "System Resources"

    printf "Disk Size: ${disk}Gb\n"
    if [[ "${disk}" -lt 300 ]]; then
        print_status "FAILED" "Disk size (${disk}Gb) is not compliant... required amount is 300Gb"
    else
        print_status "OK" "Disk size requirement achieved (${disk}Gb).."
    fi

    printf "\nNumber of CPUs: ${cpus}\n"
    if [[ "${cpus}" -lt 8 ]]; then
        print_status "FAILED" "Required CPUs is 8"
    else
        print_status "OK" "Required CPUs achieved"
    fi

    printf "\nMemory Summary (${mem}M)\n"
    if (( "${mem} < ${total_mem_required}" )); then
        print_status "FAILED" "Required memory is 32000M"
    else
        print_status "OK" "Required memory achieved"
    fi
}

check_full_filesystems() {
    local arch=$(sudo ectl ls /cbam/nodes 2>/dev/null | wc -l)
    local hostname_short=$(hostname -s)
    local host="[${hostname_short}] "

    if [[ ${arch} -eq 1 ]]; then
        host=""
        hostname_short=""
    fi

    local full_fs=$(df -hP | egrep "([80,90][0-9]|100)%")

    print_section_header "Filesystem Usage" "${hostname_short}"
    printf "${host}Checking if there are filesystems more than 80%% full...\n"

    if [[ "${#full_fs}" -gt 0 ]]; then
        echo " ${full_fs}"
        printf "\n"
    else
        print_status "OK" "No full filesystems"
    fi
}

check_ntp_and_uptime() {
    local arch=$(sudo ectl ls /cbam/nodes 2>/dev/null | wc -l)
    local hostname_short=$(hostname -s)
    local host="[${hostname_short}] "

    if [[ ${arch} -eq 1 ]]; then
        host=""
        hostname_short=""
    fi

    local deployment_date=$(stat /opt/nokia/cbam/bin/cbam-status 2>/dev/null | grep Birth | awk 'NR==1{print $2}')

    print_section_header "NTP & System Uptime" "${hostname_short}"

    printf "${host}Checking NTP sync status...\n"
    timedatectl
    printf "\n${host}System deployed date: ${deployment_date}\n"
    printf "\n${host}System Uptime: $(uptime)\n"
}
check_tsn_20241216() {
    local count=$(sudo crontab -l | grep 'rm -rf /root/.esmtp_queue' | wc -l)

    if [ "${count}" -gt 0 ]; then
        return 0  # TSN applied
    else
        return 1  # TSN not applied
    fi
}

check_tsn_20241205_db() {
    local check_manual=$(sudo crontab -l | grep 'find /root/.mongodb/mongosh -name "\\*log\\*" -mmin +60' | wc -l)
    local check_normal=$(sudo crontab -l | grep 'find /root/.mongodb/mongosh -name \*log\* -mmin +60' | wc -l)

    if [ "${check_manual}" -gt 0 ]; then
        return 0  # TSN applied with manual fix
    elif [ "${check_normal}" -gt 0 ]; then
        return 2  # TSN applied but needs manual fix
    else
        return 1  # TSN not applied
    fi
}

check_tsn_20241205_app() {
    local count=$(sudo crontab -l | grep 'rm -rf /root/.esmtp_queue/\*' | wc -l)

    if [ "${count}" -gt 0 ]; then
        return 0  # TSN applied
    else
        return 1  # TSN not applied
    fi
}

check_tsn_20241207() {
    local count=$(sudo cat /etc/sysconfig/sysstat | grep -i 'zip="gzip' | wc -l)

    if [ "${count}" -gt 0 ]; then
        return 0  # TSN applied
    else
        return 1  # TSN not applied
    fi
}

display_tsn_verification_commands() {
    local arch=$(sudo ectl ls /cbam/nodes 2>/dev/null | wc -l)
    local hostname_short=$(hostname -s)
    local host="[${hostname_short}] "

    if [[ ${arch} -eq 1 ]]; then
        host=""
        hostname_short=""
    fi

    print_section_header "TSN Verification Commands" "${hostname_short}"

    printf "\n${host}$ ls -latrh /var/log/watson | wc -l\n"
    sudo ls -latrh /var/log/watson 2>/dev/null | wc -l

    printf "\n${host}$ grep -i \"too many open\" /var/log/messages | tail -n 10\n"
    sudo grep -i "too many open" /var/log/messages 2>/dev/null | tail -n 10

    printf "\n${host}$ grep -i \"too many open\" /var/log/messages | wc -l\n"
    sudo grep -i "too many open" /var/log/messages 2>/dev/null | wc -l

    printf "\n${host}$ systemctl status rsyslog\n"
    sudo systemctl status rsyslog | cat

    if [[ $host == *"app"* || $arch == 1 ]]; then
        printf "\n${host}$ zgrep -i \"kup fin\" /var/log/cbam/backup.*\n"
        sudo zgrep -i "kup fin" /var/log/cbam/backup.* 2>/dev/null
    fi

    printf "\n${host}$ ls -latrh /root/.esmtp_queue | wc -l\n"
    sudo ls -latrh /root/.esmtp_queue 2>/dev/null | wc -l

    if [[ $host == *"db"* || $arch == 1 ]]; then
        printf "\n${host}$ ls -latrh /root/.mongodb/mongosh | wc -l\n"
        sudo ls -latrh /root/.mongodb/mongosh 2>/dev/null | wc -l
    fi

    printf "\n${host}$ crontab -l\n"
    sudo crontab -l
}

run_tsn_checks() {
    local cbam_version="$1"
    local cbam_version_full="$2"
    local host="$3"
    local arch="$4"

    if [ "${cbam_version}" -ne 24 ]; then
        return 0
    fi

    display_tsn_verification_commands "${host}" "${arch}"

    printf "\n${host}TSN Summary (v${cbam_version} // v${cbam_version_full})\n"

    case "${cbam_version_full}" in
        "24.0.1.0")
            check_tsn_20241216
            local result=$?

            if [ ${result} -eq 0 ]; then
                print_status "OK" "TSN applied: TSN-CBAM-SW-20241216_CBAM reconfiguration slowed by file pile-up due to log rotation issues in some folders" "${host}"
            else
                print_status "FAILED" "TSN not applied: TSN-CBAM-SW-20241216_CBAM reconfiguration slowed by file pile-up due to log rotation issues in some folders" "${host}"
            fi
            ;;

        "24.0.2.0")
            printf "\nNo TSNs checked for this version (CBAM 24 MP2)\n"
            ;;

        *)
            if [[ $host == *"db"* || $arch == 1 ]]; then
                check_tsn_20241205_db
                local result=$?

                if [ ${result} -eq 0 ]; then
                    print_status "OK" "TSN applied: TSN-CBAM-SW-20241205_CBAM log rotation fix (with manual quote fix)" "${host}"
                elif [ ${result} -eq 2 ]; then
                    print_status "OK" "TSN applied: TSN-CBAM-SW-20241205_CBAM log rotation fix (needs manual quote fix around *log*)" "${host}"
                else
                    print_status "FAILED" "TSN not applied: TSN-CBAM-SW-20241205_CBAM log rotation fix" "${host}"
                fi
            elif [[ $host == *"app"* || $arch == 1 ]]; then
                check_tsn_20241205_app
                local result=$?

                if [ ${result} -eq 0 ]; then
                    print_status "OK" "TSN applied: TSN-CBAM-SW-20241205_CBAM log rotation fix" "${host}"
                else
                    print_status "FAILED" "TSN not applied: TSN-CBAM-SW-20241205_CBAM log rotation fix" "${host}"
                fi
            fi

            check_tsn_20241207
            local result=$?

            if [ ${result} -eq 0 ]; then
                printf "\n"
                print_status "OK" "TSN applied: TSN_CBAM_SW_20241207 Compression Utilities Missing from CBAM and CBAM Installer Node" "${host}"
            else
                printf "\n"
                print_status "FAILED" "TSN not applied: TSN_CBAM_SW_20241207 Compression Utilities Missing from CBAM and CBAM Installer Node" "${host}"
            fi
            ;;
    esac
}

run_all_tsn_checks_wrapper() {
    local cbam_ver=$(cbam -V 2>/dev/null | awk 'NR==1{print substr($3,0,2)}')
    local cbam_ver_full=$(cbam -V 2>/dev/null | awk 'NR==1{print substr($3,0,8)}')
    local arch=$(sudo ectl ls /cbam/nodes 2>/dev/null | wc -l)
    local host_prefix="[$(hostname -s)] "

    if [[ ${arch} -eq 1 ]]; then
        host_prefix=""
    fi

    run_tsn_checks "${cbam_ver}" "${cbam_ver_full}" "${host_prefix}" "${arch}"
}

run_filesystem_and_ntp_checks() {
    check_full_filesystems

    check_ntp_and_uptime
}

check_full_filesystems() {
    local arch=$(sudo ectl ls /cbam/nodes 2>/dev/null | wc -l)
    local hostname_short=$(hostname -s)
    local host="[${hostname_short}] "

    if [[ ${arch} -eq 1 ]]; then
        host=""
        hostname_short=""
    fi

    local full_fs=$(df -hP | egrep "([80,90][0-9]|100)%")

    print_section_header "Filesystem Usage" "${hostname_short}"
    printf "${host}Checking if there are filesystems more than 80%% full...\n"

    if [[ "${#full_fs}" -gt 0 ]]; then
        echo " ${full_fs}"
        printf "\n"
    else
        print_status "OK" "No full filesystems"
    fi
}

check_ntp_and_uptime() {
    local arch=$(sudo ectl ls /cbam/nodes 2>/dev/null | wc -l)
    local hostname_short=$(hostname -s)
    local host="[${hostname_short}] "

    if [[ ${arch} -eq 1 ]]; then
        host=""
        hostname_short=""
    fi

    local deployment_date=$(stat /opt/nokia/cbam/bin/cbam-status 2>/dev/null | grep Birth | awk 'NR==1{print $2}')

    print_section_header "NTP & System Uptime" "${hostname_short}"

    printf "%sChecking NTP sync status...\n" "${host}"
    timedatectl
    printf "\n%sSystem deployed date: %s\n" "${host}" "${deployment_date}"
    printf "\n%sSystem Uptime: %s\n" "${host}" "$(uptime)"
}

DATE=$(date +%Y%m%d%H%M%S)
CBAM_BIN=/usr/bin/cbam
CBAM_CONFIG=/opt/nokia/cbam/frontend/config/versions.json
ARCH=$(sudo ectl ls /cbam/nodes 2>/dev/null | wc -l)
UUID_FILE=/etc/cbam_uuid
UUID_ETCD=$(sudo ectl get /cbam/cluster/deployment_id 2>/dev/null)
VMWARE_SERVICE=/etc/systemd/system/multi-user.target.wants/vmtoolsd.service
JQ_BIN=/usr/bin/jq

BACKUP_USER=$(sudo ectl get /cbam/cluster/components/backup/sftp/connection/username 2>/dev/null)
BACKUP_PASS=$(sudo ectl get /cbam/cluster/components/backup/sftp/connection/password 2>/dev/null)
BACKUP_HOST=$(sudo ectl get /cbam/cluster/components/backup/sftp/connection/hostname 2>/dev/null)
BACKUP_ROOT=$(sudo ectl get /cbam/cluster/components/backup/sftp/root_dir 2>/dev/null)
BACKUP_ENABLED=$(sudo ectl get /cbam/cluster/components/backup/backup_enabled 2>/dev/null)

move_uuid_to_etc() {
    sudo mv cbam_uuid /etc/.
    local uuid_value=$(sudo cat ${UUID_FILE})
    sudo chmod 400 ${UUID_FILE}
    echo "${uuid_value}"
}

backup_uuid_to_sftp() {
    local sftp_cmd="$1"
    local uuid_source="${2:-cbam_uuid}"

    export SSHPASS=${BACKUP_PASS}

    if [[ -e ${UUID_FILE} ]]; then
        uuid_source=${UUID_FILE}
    fi

    sshpass -e ${sftp_cmd} <<EOF
cd ${BACKUP_ROOT}
put ${uuid_source}
chmod 600 cbam_uuid
bye
EOF
}

get_sftp_command() {
    local ip_length=$(echo ${BACKUP_HOST} | wc -c)

    if [[ "${ip_length}" -gt 15 ]]; then
        echo "/usr/bin/sftp -oBatchMode=no -oStrictHostKeyChecking=no -b - ${BACKUP_USER}@[${BACKUP_HOST}]"
    else
        echo "/usr/bin/sftp -oBatchMode=no -oStrictHostKeyChecking=no -b - ${BACKUP_USER}@${BACKUP_HOST}"
    fi
}

upload_uuid_to_sftp() {
    local sftp_cmd=$(get_sftp_command)
    backup_uuid_to_sftp "${sftp_cmd}"
}

get_or_create_uuid() {
    local uuid_value=""

    if [ -n "${UUID_ETCD}" ]; then
        uuid_value=${UUID_ETCD}
        printf "This is CBAM22 or higher, so the UUID is on etcd parameter /cbam/cluster/deployment_id, which is also backed up on full backup.\n" >&2
        printf "/etc/cbam_uuid is not needed.\n" >&2
    elif [[ -e ${UUID_FILE} ]]; then
        uuid_value=$(sudo cat ${UUID_FILE})
    else
        uuidgen > cbam_uuid
        uuid_value=$(cat cbam_uuid)
    fi

    echo "${uuid_value}"
}

distribute_uuid_to_nodes() {
    if [ -z "${UUID_ETCD}" ]; then
        if [[ ${ARCH} -gt 1 ]] && [[ ! -e ${UUID_FILE} ]]; then
            printf "Distributing UUID to all cluster nodes...\n" >&2

            for node in $(sudo ectl ls cbam/nodes 2>/dev/null | awk '{print substr($0,13)}' | grep -v "$(hostname -s)"); do
                scp cbam_uuid cbam@${node}:~/.
                ssh -q cbam@${node} 'sudo mv cbam_uuid /etc/.; sudo chmod 400 /etc/cbam_uuid'
            done
        fi
    fi
}

handle_uuid_backup() {
    local uuid_value="$1"

    if [ -n "${UUID_ETCD}" ]; then
        return 0
    fi

    if [ -n "${BACKUP_ENABLED}" ]; then
        if [ "${BACKUP_ENABLED}" == "true" ]; then
            printf "Starting the backup of cbam_uuid to sftp server...\n\n" >&2
            upload_uuid_to_sftp
        else
            printf "Backup is not enabled, cbam_uuid will not be uploaded...\n\n" >&2
        fi
    elif [[ -z "${BACKUP_USER}" ]]; then
        printf "Parameter backup_enable doesn't exist and sftp user not configured. Will not upload UUID...\n\n" >&2
    else
        printf "Parameter backup_enable doesn't exist, but sftp user is configured. Trying to upload UUID...\n\n" >&2
        upload_uuid_to_sftp
    fi
}

detect_platform() {
    if [[ -e ${VMWARE_SERVICE} ]]; then
        echo "VMWare"
    else
        echo "Openstack"
    fi
}

get_architecture_type() {
    if [[ ${ARCH} -eq 1 ]]; then
        echo "Single"
    else
        echo "HA"
    fi
}

get_cbam_build() {
    if [ -n "${CBAM_BIN}" ] && [ -e "${CBAM_BIN}" ]; then
        ${CBAM_BIN} -V 2>/dev/null | awk 'NR==1{print substr($3,1,8)}'
    else
        cat ${CBAM_CONFIG} 2>/dev/null | head -3 | tail -1 | cut -c20-100 | awk '{print substr($1,2,8)}'
    fi
}

create_inventory_json() {
    local uuid_value="$1"
    local build_version="$2"
    local architecture="$3"
    local platform="$4"
    local customer="$5"
    local instance="$6"

    local json_string=""

    if [[ -e ${JQ_BIN} ]]; then
        json_string=$(jq -n \
            --arg Uu "${uuid_value}" \
            --arg ts "${DATE}" \
            --arg Rel "${build_version}" \
            --arg Arch "${architecture}" \
            --arg Host "${platform}" \
            --arg Prod "CBAM" \
            '{Uuid: $Uu, timestamp: $ts, Release: $Rel, Architecture: $Arch, Host: $Host, Product: $Prod}')
    else
        printf "The tool ${JQ_BIN} doesn't exist, will create json file manually...\n\n" >&2
        json_string='{"Uuid":"'"${uuid_value}"'","timestamp":"'"${DATE}"'","Release":"'"${build_version}"'","Architecture":"'"${architecture}"'","Host":"'"${platform}"'","Product":"CBAM"}'
    fi

    echo -e "\n" >&2

    local json_filename="cbam_${uuid_value}_${DATE}.json"
    echo ${json_string} > "${json_filename}"
    sudo chmod 444 "${json_filename}"

    echo "${json_filename}"
}

create_ncib_zip() {
    local json_filename="$1"
    local customer="$2"
    local instance="$3"
    local uuid_value="$4"

    printf "Collecting data to create .zip for NCIB tool...\n\n" >&2

    printf "Customer name is: ${customer}\n\n" >&2
    printf "Instance name is: ${instance}\n\n" >&2

    if [ -z "${customer}" ] || [ -z "${instance}" ]; then
        printf "Customer or Instance Name not provided, ZIP file will not be created.\n\n" >&2
    else
        printf "Creating ZIP file to upload to NCIB.\n\n" >&2
        zip -r "CBAM-INV_${customer}_${instance}_NCR_CBAM_${uuid_value}_${DATE}.zip" "${json_filename}"
    fi
}

run_platform_check() {
    local customer="$1"
    local instance="$2"

    local build_version=$(get_cbam_build)

    local uuid_value=$(get_or_create_uuid)

    local architecture=$(get_architecture_type)

    handle_uuid_backup "${uuid_value}"

    distribute_uuid_to_nodes

    if [ -z "${UUID_ETCD}" ]; then
        if [[ ${ARCH} -eq 1 ]] && [[ ! -e ${UUID_FILE} ]]; then
            uuid_value=$(move_uuid_to_etc)
        elif [[ ${ARCH} -gt 1 ]] && [[ ! -e ${UUID_FILE} ]]; then
            uuid_value=$(move_uuid_to_etc)
        fi
    fi

    local platform=$(detect_platform)

    local json_filename=$(create_inventory_json "${uuid_value}" "${build_version}" "${architecture}" "${platform}" "${customer}" "${instance}")

    create_ncib_zip "${json_filename}" "${customer}" "${instance}" "${uuid_value}"
}


LOG_DIR=/var/log
CBAM_LOG_DIR=/var/log/cbam
CBAM_OTHER_LOG_DIR=/var/log/cbam_other

HOSTNAME=$(hostname -s)
NODES_DB=$(sudo ectl ls cbam/nodes 2>/dev/null | awk '{print substr($0,13)}' | grep db)
NODES_APP=$(sudo ectl ls cbam/nodes 2>/dev/null | awk '{print substr($0,13)}' | grep app)
SSH_KEY=/home/cbam/.ssh/id_rsa
VMWARE_SERVICE=/etc/systemd/system/multi-user.target.wants/vmtoolsd.service

CBAM_BIN=/usr/bin/cbam
CBAM_CONFIG=/opt/nokia/cbam/frontend/config/versions.json
ARCHITECTURE=$(sudo ectl ls /cbam/nodes 2>/dev/null | wc -l)

HOST_PREFIX="[${HOSTNAME}] "
if [[ ${ARCHITECTURE} -eq 1 ]]; then
    HOST_PREFIX=""
fi

get_cbam_version() {
    if [ -n "${CBAM_BIN}" ] && [ -e "${CBAM_BIN}" ]; then
        ${CBAM_BIN} -V 2>/dev/null | awk 'NR==1{print $3}'
    else
        cat ${CBAM_CONFIG} 2>/dev/null | head -3 | tail -1 | cut -c20-100 | awk '{print substr($1,2,23)}'
    fi
}

run_bvt_checks() {
    if ! validate_cbam_system; then
        printf "\n❌ ERROR: System validation failed. Exiting...\n\n"
        exit 1
    fi

    if ! validate_ha_active_node; then
        printf "\n❌ ERROR: HA node validation failed. Exiting...\n\n"
        printf "This script must be run on the active APP node for HA deployments.\n\n"
        exit 1
    fi

    local cbam_version=$(get_cbam_version)
    local current_datetime=$(date '+%Y-%m-%d %H:%M:%S %Z')

    printf "\nBVT triggered on: ${HOSTNAME} at ${current_datetime}\n"
    printf "\nCBAM version is: ${cbam_version}\n"
    printf "\nCBAM is on top of: "
    if [[ -e ${VMWARE_SERVICE} ]]; then
        echo "VMWare"
    else
        echo "Openstack"
    fi
    printf "\n"

    print_section_header "CBAM Status"
    /opt/nokia/cbam/bin/cbam-status

    print_section_header "Cluster Health"
    sudo ectl cluster-health

    print_section_header "I/O Performance - iostat"
    iostat

    print_section_header "I/O Performance - FIO Write Test"
    printf "FIO FS Write test (512Mb/10sec/Target 1100 IOPS):\n"
    fio --name=random-write --rate_iops=1100 --ioengine=posixaio --rw=randwrite --bs=64k --size=512m --numjobs=1 --iodepth=16 --runtime=5 --time_based --end_fsync=1 --unlink=1

    print_section_header "I/O Performance - FIO Read Test"
    printf "FIO FS Read test (512Mb/10sec/Target 1100 IOPS):\n"
    fio --name=random-read --rate_iops=1100 --ioengine=posixaio --rw=randread --bs=64k --size=512m --numjobs=1 --iodepth=1 --runtime=5 --time_based --end_fsync=1 --unlink=1

    if [[ ${ARCHITECTURE} -eq 1 ]]; then
        check_single_node_resources

        check_full_filesystems

        check_ntp_and_uptime

        local cbam_ver=$(cbam -V 2>/dev/null | awk 'NR==1{print substr($3,0,2)}')
        local cbam_ver_full=$(cbam -V 2>/dev/null | awk 'NR==1{print substr($3,0,8)}')
        run_tsn_checks "${cbam_ver}" "${cbam_ver_full}" "${HOST_PREFIX}" "${ARCHITECTURE}"

    else
        for node in ${NODES_APP}; do
            ssh -oStrictHostKeyChecking=no -q -i ${SSH_KEY} cbam@${node} "$(declare -f print_section_header print_status check_app_node_resources); check_app_node_resources"
            ssh -oStrictHostKeyChecking=no -q -i ${SSH_KEY} cbam@${node} "$(declare -f print_section_header print_status check_full_filesystems); check_full_filesystems"
            ssh -oStrictHostKeyChecking=no -q -i ${SSH_KEY} cbam@${node} "$(declare -f print_section_header check_ntp_and_uptime); check_ntp_and_uptime"
            ssh -oStrictHostKeyChecking=no -q -i ${SSH_KEY} cbam@${node} "$(declare -f print_section_header display_tsn_verification_commands); display_tsn_verification_commands"
            ssh -oStrictHostKeyChecking=no -q -i ${SSH_KEY} cbam@${node} "$(declare -f print_status check_tsn_20241216 check_tsn_20241205_app check_tsn_20241207 run_tsn_checks run_all_tsn_checks_wrapper); run_all_tsn_checks_wrapper"
        done

        for node in ${NODES_DB}; do
            ssh -oStrictHostKeyChecking=no -q -i ${SSH_KEY} cbam@${node} "$(declare -f print_section_header print_status check_db_node_resources); check_db_node_resources"
            ssh -oStrictHostKeyChecking=no -q -i ${SSH_KEY} cbam@${node} "$(declare -f print_section_header print_status check_full_filesystems); check_full_filesystems"
            ssh -oStrictHostKeyChecking=no -q -i ${SSH_KEY} cbam@${node} "$(declare -f print_section_header check_ntp_and_uptime); check_ntp_and_uptime"
            ssh -oStrictHostKeyChecking=no -q -i ${SSH_KEY} cbam@${node} "$(declare -f print_section_header display_tsn_verification_commands); display_tsn_verification_commands"
            ssh -oStrictHostKeyChecking=no -q -i ${SSH_KEY} cbam@${node} "$(declare -f print_status check_tsn_20241216 check_tsn_20241205_db check_tsn_20241207 run_tsn_checks run_all_tsn_checks_wrapper); run_all_tsn_checks_wrapper"
        done
    fi

    check_network_configuration

    check_snmp_configuration

    check_cbam_size

    display_active_alarms

    check_backup_configuration

    check_georedundancy

    check_all_logs_in_directory "${CBAM_LOG_DIR}" "vnf\|alma\|workflows\|grow_cluster\|\*\*no"
    check_all_logs_in_directory "${CBAM_OTHER_LOG_DIR}" "watson"

    printf "\n\nThis BVT was performed on: $(date)\n\n"
    printf "BVT DONE...\n\n"
}

main

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

print_bordered() {
    local text="$1"
    local length=${#text}
    local border=$(printf '+%*s+' $((length + 2)) | tr ' ' '-')

    echo "${border}"
    echo "| ${text} |"
    echo "${border}"
}

prompt_input() {
    local prompt_text="$1"
    local variable_name="$2"
    local input_value

    printf "${BLUE}${prompt_text}${NC} "
    read input_value

    input_value="${input_value// /-}"

    eval "${variable_name}='${input_value}'"
}

main() {
    clear
    echo ""
    print_bordered "CBAM Base Viability Test (BVT) - Version 23"
    echo ""

    if [[ "${VERBOSE_MODE}" == "true" ]]; then
        printf "${YELLOW}Running in verbose mode (screen output only)${NC}\n"
        echo ""
        echo ""
        print_bordered "Using BVT version 23"
        echo ""

        export COLORIZE_OUTPUT=true
        run_bvt_checks 2>&1

        echo ""
        printf "${GREEN}═══════════════════════════════════════${NC}\n"
        printf "${GREEN}BVT execution completed!${NC}\n"
        printf "${GREEN}═══════════════════════════════════════${NC}\n"
        echo ""
        return
    fi

    prompt_input "Insert customer name:" CUSTOMER
    prompt_input "Insert Instance name:" INSTANCE
    echo ""
    printf "${YELLOW}Collecting data... this may take a few minutes${NC}\n"
    echo ""

    HOSTNAME_SHORT=$(hostname -s)
    TIMESTAMP=$(date +%Y%m%d_%H%M%S)
    OUTPUT_FILE="bvt_${HOSTNAME_SHORT}_${TIMESTAMP}.txt"

    {
        echo ""
        print_bordered "Using BVT version 23"
        echo ""
    } > "${OUTPUT_FILE}"

    printf "${GREEN}Running main BVT checks...${NC}\n"
    if run_bvt_checks >> "${OUTPUT_FILE}" 2>&1; then
        printf "${GREEN}✓ Main BVT checks completed${NC}\n"
    else
        printf "${RED}✗ Main BVT checks encountered errors${NC}\n"
    fi

    printf "${GREEN}Running platform detection and inventory creation...${NC}\n"
    if run_platform_check "${CUSTOMER}" "${INSTANCE}" >> "${OUTPUT_FILE}" 2>&1; then
        printf "${GREEN}✓ Platform checks completed${NC}\n"
    else
        printf "${RED}✗ Platform checks encountered errors${NC}\n"
    fi

    echo ""
    printf "${GREEN}═══════════════════════════════════════${NC}\n"
    printf "${GREEN}BVT execution completed!${NC}\n"
    printf "${GREEN}═══════════════════════════════════════${NC}\n"
    echo ""

    # Collect all generated files for final packaging
    local json_file=$(ls cbam_*.json 2>/dev/null | tail -1)
    local ncib_zip=$(ls CBAM-INV_*.zip 2>/dev/null | tail -1)
    local files_to_zip="${OUTPUT_FILE}"

    if [ -n "${json_file}" ]; then
        files_to_zip="${files_to_zip} ${json_file}"
    fi

    if [ -n "${ncib_zip}" ]; then
        files_to_zip="${files_to_zip} ${ncib_zip}"
    fi

    # Create final ZIP with all outputs
    local final_zip="BVT_${CUSTOMER}_${INSTANCE}_${HOSTNAME_SHORT}_${TIMESTAMP}.zip"
    printf "${GREEN}Creating final package...${NC}\n"
    if zip -j "${final_zip}" ${files_to_zip} > /dev/null 2>&1; then
        printf "${GREEN}✓ Package created: ${final_zip}${NC}\n"

        # Delete original files after successful zip creation
        rm -f ${files_to_zip}
        printf "${GREEN}✓ Original files cleaned up${NC}\n"
    else
        printf "${RED}✗ Failed to create package, keeping original files${NC}\n"
    fi

    echo ""
    printf "Final output: ${BLUE}${final_zip}${NC}\n"
    echo ""
}

VERBOSE_MODE=false
while [[ $# -gt 0 ]]; do
    case "$1" in
        -v|--verbose)
            VERBOSE_MODE=true
            shift
            ;;
        -h|--help)
            echo "Usage: $(basename "$0") [-v|--verbose] [-h|--help]"
            echo ""
            echo "Options:"
            echo "  -v, --verbose    Output to screen only (no files created)"
            echo "  -h, --help       Show this help message"
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            echo "Use -h or --help for usage information"
            exit 1
            ;;
    esac
done

main
