# Dell PowerEdge Fan Speed Controller for iDRAC 9
This project provides a custom solution to control fan speed on Dell PowerEdge servers equipped with iDRAC 9 for bothe CPU and GPU servers. The default 30% fan speed set by Dell is too aggressive for environments like home labs or personal file servers, where noise reduction is a priority. This script aims to maintain a quieter operation while ensuring that cooling remains effective during higher workloads.

Inspired by : https://github.com/tigerblue77/Dell_iDRAC_fan_controller for idrac 7 servers. ( needed the additionnal GPU support and idrac 9 fixes )   
 

## Overview 
For most scenarios, such as running a file server with occasional services and infrequent AI training, the script adjusts the baseline fan speed to a quiet 7%. Fans will ramp up quickly if the CPU exceeds 50°C or the GPU exceeds 60°C to maintain optimal temperatures. The system utilizes chassis fans to passively cool the GPUs.

### Tested Configuration

- **Server Model:** Dell PowerEdge 7920 Rack (Single CPU)
- **GPU:** NVIDIA Tesla (Passively Cooled by Chassis Fans)

### Important Requirements

- **iDRAC Firmware Version:** 3.30.30.30
  - *Note:* Newer versions do not allow manual override via IPMI. If necessary, downgrade your firmware to the specified version to enable this feature.

## Getting Started

### Prerequisites

- Docker installed on your system.
- Access to iDRAC 9 on your Dell PowerEdge server.

### Building the Docker Image

To get started, you'll need to build the Docker image that will run the fan control script. Clone the repository and navigate to the project directory:

```bash
git clone https://github.com/xsmarty/idrac9_fan_controller.git fan-controller
cd your-repo-directory
docker build -t fan-controller .
```

### Running the Docker Container

The script supports two modes for connecting to iDRAC: over the network or locally. You can configure these modes and other settings using environment variables.
Environment Variables
```bash
    IDRAC_HOST: The IP address of your iDRAC interface. Set to local if running on the same machine.
    IDRAC_USERNAME: Your iDRAC username. Default is root.
    IDRAC_PASSWORD: Your iDRAC password. Default is calvin.
    FAN_BASELINE: The baseline fan speed percentage. Default is 7.
    CPU_TEMPERATURE_THRESHOLD: The CPU temperature in Celsius at which fans will ramp up. Default is 50.
    GPU_TEMPERATURE_THRESHOLD: The GPU temperature in Celsius at which fans will ramp up. Default is 60.
```
Example Command

Here's how you might run the Docker container with custom settings:

```bash
docker run -d \
  -e IDRAC_HOST=192.168.1.1 \
  -e IDRAC_USERNAME=root \
  -e IDRAC_PASSWORD=calvin \
  -e FAN_BASELINE=7 \
  -e CPU_TEMPERATURE_THRESHOLD=50 \
  -e GPU_TEMPERATURE_THRESHOLD=60 \
  fan-controller
```
Note: It is recommended to override these default values to suit your specific environment and needs.
Local Mode Example

If you are running the script locally on the server (without network access to iDRAC), you can set IDRAC_HOST to local:

```bash

docker run -d \
  -e IDRAC_HOST=local \
  -e FAN_BASELINE=7 \
  -e CPU_TEMPERATURE_THRESHOLD=50 \
  -e GPU_TEMPERATURE_THRESHOLD=60 \
  fan-controller
```
Verifying the Setup

Once the container is running, it will automatically adjust the fan speeds based on the thresholds you've set. You can check the logs to verify that everything is working correctly:

```bash
docker logs -f <container_id>
```
