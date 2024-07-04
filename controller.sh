#!/bin/bash
# Inspired by : https://github.com/tigerblue77/Dell_iDRAC_fan_controller/ Forked for Idrac9 
# "Works on my computer" : PowerEdge 7920 Rack 2CPU + GPU
# REQUIRES iDRAC Firmware Version 3.30.30.30. Anything newer does not allow manual override ! 


source functions.sh

# Trap the signals for container exit and run gracefull_exit function
trap 'gracefull_exit' SIGQUIT SIGKILL SIGTERM SIGINT 

# Check if the iDRAC host is set to 'local' or not then set the IDRAC_LOGIN_STRING accordingly
if [[ $IDRAC_HOST == "local" ]]
then
  # Check that the Docker host IPMI device (the iDRAC) has been exposed to the Docker container
  if [ ! -e "/dev/ipmi0" ] && [ ! -e "/dev/ipmi/0" ] && [ ! -e "/dev/ipmidev/0" ]; then
    echo "/!\ Could not open device at /dev/ipmi0 or /dev/ipmi/0 or /dev/ipmidev/0, check that you added the device to your Docker container or stop using local mode. Exiting." >&2
    exit 1
  fi
  IDRAC_LOGIN_STRING='open'
else
  echo "iDRAC/IPMI username: $IDRAC_USERNAME"
  echo "iDRAC/IPMI password: $IDRAC_PASSWORD"
  IDRAC_LOGIN_STRING="lanplus -H $IDRAC_HOST -U $IDRAC_USERNAME -P $IDRAC_PASSWORD"
fi

# Declare associative arrays globally
declare -A gpu_temperatures
declare -A cpu_temperatures
declare -A inlet_temperatures
declare -A exhaust_temperatures

# GPU target temperature from ENV 
#GPU_TEMPERATURE_THRESHOLD=65
# CPU target temperature from ENV 
#CPU_TEMPERATURE_THRESHOLD=50
# FAN minimum speed from ENV 
#FAN_BASELINE=7

fan_speed=$FAN_BASELINE

# Function to retrieve GPU sensor temperatures
function get_gpu_info {
    mapfile -t gpu_sensors < <(ipmitool -I $IDRAC_LOGIN_STRING sensor list | grep -i "gpu")
    local gpu_count=0

    echo "Processing GPU Sensors:"
    for i in "${!gpu_sensors[@]}"; do
        local gpu_index=$((i + 1))
        local sensor="${gpu_sensors[i]}"
        local sensor_name=$(echo "$sensor" | awk -F'|' '{print $1}' | sed 's/^\s*//;s/\s*$//')  # Trim whitespace
        local temperature=$(echo "$sensor" | awk -F'|' '{print $2}' | tr -d ' degrees C' | awk '{print int($1)}')
        
        if [[ "$temperature" == 0 ]]; then
            continue  # Skip this GPU as it reports a temperature of 0°C
        fi
        
        if [[ ! "$temperature" =~ ^[0-9]+$ ]]; then
            temperature=-1
        fi

        gpu_temperatures[$sensor_name]=$temperature
        ((gpu_count++))
        echo "$sensor_name: ${gpu_temperatures[$sensor_name]}°C"
    done

    echo "Number of GPUs found with non-zero temperature: $gpu_count"
}

# Function to retrieve CPU sensor temperatures
function get_cpu_info {
    mapfile -t cpu_sensors < <(ipmitool -I $IDRAC_LOGIN_STRING sensor list | grep -E '^\s*Temp\s*\|')
    local cpu_count=0

    echo "Processing CPU Sensors:"
    for i in "${!cpu_sensors[@]}"; do
        local cpu_index=$((i + 1))
        local sensor="${cpu_sensors[i]}"
        local sensor_name=$(echo "$sensor" | awk -F'|' '{print $1}' | sed 's/^\s*//;s/\s*$//')  # Trim whitespace # ipmi uses Temp without CPU
        local temperature=$(echo "$sensor" | awk -F'|' '{print $2}' | tr -d ' degrees C' | awk '{print int($1)}')
        
        if [[ "$temperature" == 0 ]]; then
            continue  # Skip this CPU as it reports a temperature of 0°C
        fi

        if [[ ! "$temperature" =~ ^[0-9]+$ ]]; then
            temperature=-1
        fi

        cpu_temperatures[$cpu_index]=$temperature
        ((cpu_count++))
        echo "CPU$cpu_index : ${cpu_temperatures[$cpu_index]}°C"
    done

    echo "Number of CPUs found with non-zero temperature: $cpu_count"
}

# Function to check if any GPU is overheating
function check_overheating_gpus {
    local threshold=$1
    echo "Checking GPUs for overheating with threshold: $threshold°C"
    for key in "${!gpu_temperatures[@]}"; do
        local temperature=${gpu_temperatures[$key]}
        if [[ "$temperature" -gt "$threshold" ]]; then
            echo "$key is overheating! Current temperature: $temperature°C, threshold: $threshold°C"
            return 0
        fi
    done
    echo "No GPUs are overheating."
    return 1
}

# Function to check if any CPU is overheating
function check_overheating_cpus {
    local threshold=$1
    echo "Checking CPUs for overheating with threshold: $threshold°C"
    for key in "${!cpu_temperatures[@]}"; do
        local temperature=${cpu_temperatures[$key]}
        if [[ "$temperature" -gt "$threshold" ]]; then
            echo "$key is overheating! Current temperature: $temperature°C, threshold: $threshold°C"
            return 0
        fi
    done
    echo "No CPUs are overheating."
    return 1
}

# PID function to adjust fan speed based on temperature
function adjust_fan_speed {
    local target_temp=$1
    local actual_temp=$2

    local error=$((actual_temp - target_temp))

    if [[ error -le 0 ]]; then
        fan_speed=$FAN_BASELINE
        echo "Setting fan speed to $fan_speed%"
    else
        # Proportional control: increment fan speed by 10% for each degree above target
        fan_speed=$((error * 10))

        # Cap fan speed at 100%
        if [[ fan_speed -gt 100 ]]; then
            fan_speed=100
        fi
        echo "Setting fan speed to $fan_speed%"
    fi

    
    HEXADECIMAL_FAN_SPEED=$(printf '0x%02x' $fan_speed)
    # Use ipmitool to send the raw command to set fan control to user-specified value
    # Should these fail, use 
    ipmitool -I $IDRAC_LOGIN_STRING raw 0x30 0x30 0x01 0x00 > /dev/null
    ipmitool -I $IDRAC_LOGIN_STRING raw 0x30 0x30 0x02 0xff $HEXADECIMAL_FAN_SPEED > /dev/null 

    # e.g., some_command_to_set_fan_speed $fan_speed
}

# Retrieve and process both GPU and CPU sensor temperatures
function get_sensor_info {
    # Fetch only temperature sensor data
    local sensors_output
    mapfile -t sensors_output < <(ipmitool -I $IDRAC_LOGIN_STRING sdr type temperature | grep "degrees")

    local gpu_count=0
    local cpu_count=0
    local inlet_count=0
    local exhaust_count=0

    #echo "Processing Sensor Information:"
    for sensor_line in "${sensors_output[@]}"; do
        local sensor_name=$(echo "$sensor_line" | awk -F'|' '{print $1}' | sed 's/^\s*//;s/\s*$//')
        local temperature=$(echo "$sensor_line" | awk -F'|' '{print $5}' | tr -d ' degrees C' | awk '{print int($1)}')

        # Process GPU sensors
        if [[ "$sensor_name" == *"GPU"* && "$temperature" -gt 0 ]]; then
            gpu_temperatures[$sensor_name]=$temperature
            ((gpu_count++))
            #echo "$sensor_name: ${gpu_temperatures[$sensor_name]}°C"
        fi

        # Process CPU sensors that strictly contain "Temp"
        if [[ "$sensor_name" == "Temp" && "$temperature" -gt 0 ]]; then
            local cpu_index=$((cpu_count + 1))
            cpu_temperatures[CPU$cpu_index]=$temperature
            ((cpu_count++))
            #echo "CPU$cpu_index: ${cpu_temperatures[CPU$cpu_index]}°C"
        fi

        # Process Inlet sensors
        if [[ "$sensor_name" == *"Inlet"* && "$temperature" -gt 0 ]]; then
            local inlet_index=$((inlet_count + 1))
            inlet_temperatures[$sensor_name]=$temperature
            ((inlet_count++))
            #echo "$sensor_name: ${inlet_temperatures[$sensor_name]}°C"
        fi

        # Process Exhaust sensors
        if [[ "$sensor_name" == *"Exhaust"* && "$temperature" -gt 0 ]]; then
            local exhaust_index=$((exhaust_count + 1))
            exhaust_temperatures[$sensor_name]=$temperature
            ((exhaust_count++))
            #echo "$sensor_name: ${exhaust_temperatures[$sensor_name]}°C"
        fi
    done

    #echo "Number of GPUs found with non-zero temperature: $gpu_count"
    #echo "Number of CPUs found with non-zero temperature: $cpu_count"
    #echo "Number of Inlets found with non-zero temperature: $inlet_count"
    #echo "Number of Exhausts found with non-zero temperature: $exhaust_count"
}

# Function to display temperatures in a table format
function display_temperature_table {
    local current_date_time=$(date "+%Y-%m-%d %H:%M:%S")
    local max_cpu_temp=0
    local max_cpu_id=""
    local max_gpu_temp=0
    local max_gpu_id=""
    local inlet_temp="${inlet_temperatures['Inlet Temp']:-N/A}"
    local exhaust_temp="${exhaust_temperatures['Exhaust Temp']:-N/A}"
 #   local fan_speed="50%"  # Example fan speed, adapt as necessary

    # Find maximum CPU temperature
    for key in "${!cpu_temperatures[@]}"; do
        if [[ "${cpu_temperatures[$key]}" -gt "$max_cpu_temp" ]]; then
            max_cpu_temp=${cpu_temperatures[$key]}
            max_cpu_id=$key
        fi
    done

    # Find maximum GPU temperature
    for key in "${!gpu_temperatures[@]}"; do
        if [[ "${gpu_temperatures[$key]}" -gt "$max_gpu_temp" ]]; then
            max_gpu_temp=${gpu_temperatures[$key]}
            max_gpu_id=$key
        fi
    done

    # Ensure temperatures are displayed as 'N/A' if not found
    max_cpu_temp=${max_cpu_temp:-N/A}
    max_gpu_temp=${max_gpu_temp:-N/A}

    # Print table data
    printf "%-20s IN: %-10s %-15s %-15s %-15s %-15s OUT: %-10s Fan: %-10s\n" "$current_date_time" "$inlet_temp°C" "$max_cpu_id"  "$max_cpu_temp°C($CPU_TEMPERATURE_THRESHOLD°C)" "$max_gpu_id" "$max_gpu_temp°C($GPU_TEMPERATURE_THRESHOLD°C)" "$exhaust_temp°C" "$fan_speed"
}

# Function to check if there is overheating
function is_overheating {
    local highest_diff=$1
    # If the difference exceeds a critical threshold (e.g., 10 degrees over target), consider it overheating
    [[ $highest_diff -gt 10 ]]
}


# Main execution function
function main {
    local sleep_duration=5 # default sleep duration in seconds
    while true; do

        #echo "Retrieving Sensor Information from $IPMI_HOST..."
        #get_gpu_info
        #get_cpu_info
        get_sensor_info

        display_temperature_table

        local highest_diff=0
        local actual_temp_for_highest_diff=0
        local target_temp_for_highest_diff=0

        #check_overheating_gpus $GPU_TEMPERATURE_THRESHOLD
        #check_overheating_cpus $CPU_TEMPERATURE_THRESHOLD

        # Check GPUs
        for key in "${!gpu_temperatures[@]}"; do
            local diff=$((gpu_temperatures[$key] - GPU_TEMPERATURE_THRESHOLD))
            if [[ $diff -gt $highest_diff ]]; then
                highest_diff=$diff
                actual_temp_for_highest_diff=${gpu_temperatures[$key]}
                target_temp_for_highest_diff=$GPU_TEMPERATURE_THRESHOLD
            fi
        done

        # Check CPUs
        for key in "${!cpu_temperatures[@]}"; do
            local diff=$((cpu_temperatures[$key] - CPU_TEMPERATURE_THRESHOLD))
            if [[ $diff -gt $highest_diff ]]; then
                highest_diff=$diff
                actual_temp_for_highest_diff=${cpu_temperatures[$key]}
                target_temp_for_highest_diff=$CPU_TEMPERATURE_THRESHOLD
            fi
        done

        # Adjust fan speed based on the highest temperature difference found
        adjust_fan_speed $target_temp_for_highest_diff $actual_temp_for_highest_diff

        # Determine sleep duration based on whether there is overheating
        if is_overheating $highest_diff; then
            #apply_Dell_fan_control_profile
            sleep_duration=1
        else
            sleep_duration=5
        fi
        # Sleep for the specified interval before taking another reading, allows interruption
        sleep $sleep_duration &
        SLEEP_PROCESS_PID=$!
        wait $SLEEP_PROCESS_PID
    done
}

main

