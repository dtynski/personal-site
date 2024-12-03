

#!/bin/bash

# ASCII art for Frigate
echo "
  ______                  _____           _        _ _       _   _             
 |  ____|                |_   _|         | |      | | |     | | (_)            
 | |__   __ _ ___ _   _    | |  _ __  ___| |_ __ _| | | __ _| |_ _  ___  _ __  
 |  __| / _\` / __| | | |   | | | '_ \/ __| __/ _\` | | |/ _\` | __| |/ _ \| '_ \ 
 | |___| (_| \__ \ |_| |  _| |_| | | \__ \ || (_| | | | (_| | |_| | (_) | | | |
 |______\__,_|___/\__, | |_____|_| |_|___/\__\__,_|_|_|\__,_|\__|_|\___/|_| |_|
                   __/ |                                                       
                  |___/                                                        

"


SETTINGS_FILE="./frigate_installation_settings"
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

# Function to prompt user for folder path
prompt_for_folder() {
  local folder_type="$1"
  read -p "Enter the folder path for ${folder_type} folder: " folder_path
  if [ ! -d "$folder_path" ]; then
    mkdir -p "$folder_path" || { echo "Error creating folder. Exiting."; exit 1; }
  fi
  echo "$folder_path"
}

# Function to stop Frigate container
stop_frigate_container() {
  echo "Stopping Frigate container..."
  docker stop frigate &>/dev/null
  echo "Frigate container stopped."
}

# Function to delete Frigate installation
delete_frigate_installation() {
  echo "Stopping and deleting Frigate containers..."

  # Stop any running Frigate container
  docker stop frigate &>/dev/null

  # Remove Frigate containers (both running and stopped)
  docker rm -f $(docker ps -a -q -f name=frigate) &>/dev/null

  # Add additional cleanup steps if needed

  # Delete the configuration file
  rm -f "$SETTINGS_FILE"
  echo "Deleted Frigate installation and configuration file: $SETTINGS_FILE"

  echo "Frigate installation deleted."
}


# Function to check if Docker is installed
check_docker() {
  if ! command -v docker &>/dev/null; then
    echo "Error: Docker not found. Installing Docker..."
    sudo apt-get update
    sudo apt-get install -y docker.io
    sudo usermod -aG docker "$USER" || { echo "Error adding user to docker group. Exiting."; exit 1; }
    echo "Docker installed successfully. Please log out and log back in to apply Docker group changes."
    echo "Press Enter when you have logged back in."
    read -r
    exit
  fi
}

# Function to check if dependencies (curl and jq) are installed
check_dependencies() {
  if ! command -v curl &>/dev/null || ! command -v jq &>/dev/null; then
    echo "Dependencies not found. Installing curl and jq..."
    sudo apt-get update
    sudo apt-get install -y curl jq
    echo "Dependencies installed successfully."
  fi
}

# Function to load configuration from file if it exists
load_configuration() {
  if [ -f "$SETTINGS_FILE" ]; then
    source "$SETTINGS_FILE"
  fi
}

# Function to prompt user for Frigate version
get_frigate_version() {
  load_configuration

  if [ -z "$FRIGATE_VERSION" ]; then
    read -p "Do you want to install the stable version or beta? Enter 'stable' or 'beta': " frigate_version
    case "$frigate_version" in
      stable)
        FRIGATE_IMAGE="ghcr.io/blakeblackshear/frigate:stable"
        ;;
      beta)
        get_latest_beta_version
        FRIGATE_IMAGE="ghcr.io/blakeblackshear/frigate:$LATEST_BETA_VERSION"
        ;;
      *)
        echo "Invalid option. Exiting."
        exit 1
        ;;
    esac
    echo "FRIGATE_VERSION=$frigate_version" >> "$SETTINGS_FILE"
  else
    echo "Using Frigate version from the configuration file: $FRIGATE_VERSION"
  fi
}

# Function to get the latest Frigate beta version from GitHub
get_latest_beta_version() {
  echo "Fetching the latest Frigate beta version..."
  LATEST_BETA_VERSION=$(curl -s https://github.com/blakeblackshear/frigate/tags | grep -o 'v[0-9]\+\.[0-9]\+\.[0-9]\+-beta[0-9]\+' | sort -V | tail -n 1 | sed 's/^v//')
  if [ -z "$LATEST_BETA_VERSION" ]; then
    echo "Error fetching the latest beta version. Exiting."
    exit 1
  fi
  echo "Latest Frigate beta version: $LATEST_BETA_VERSION"
}

# Function to prompt user for media folder
prompt_for_media_folder() {
  MEDIA_FOLDER=$(prompt_for_folder "Media")
  echo "MEDIA_FOLDER=$MEDIA_FOLDER" >> "$SETTINGS_FILE"
}

# Function to prompt user for GPU choice
prompt_for_gpu() {
  read -p "Do you want to use an NVIDIA GPU? (yes/no): " use_gpu
  case "$use_gpu" in
    yes)
      USE_GPU=true
      ;;
    no)
      USE_GPU=false
      ;;
    *)
      echo "Invalid option. Exiting."
      exit 1
      ;;
  esac
  echo "USE_GPU=$USE_GPU" >> "$SETTINGS_FILE"
}

# Function to prompt user for Coral USB choice
prompt_for_coral() {
  read -p "Do you want to use a Coral USB device? (yes/no): " use_coral
  case "$use_coral" in
    yes)
      USE_CORAL=true
      ;;
    no)
      USE_CORAL=false
      ;;
    *)
      echo "Invalid option. Exiting."
      exit 1
      ;;
  esac
  echo "USE_CORAL=$USE_CORAL" >> "$SETTINGS_FILE"
}

# Function to pull Frigate image
pull_frigate_image() {
  load_configuration

  # Ensure that the latest beta version is retrieved dynamically
  get_latest_beta_version

  if [ -z "$FRIGATE_IMAGE" ]; then
    echo "Pulling Frigate image..."
    FRIGATE_IMAGE="ghcr.io/blakeblackshear/frigate:$LATEST_BETA_VERSION"
    echo "Using Frigate image from the configuration file: $FRIGATE_IMAGE"
  else
    echo "Using Frigate image from the configuration file: $FRIGATE_IMAGE"
  fi

  docker pull "$FRIGATE_IMAGE" || { echo "Error pulling Frigate image. Exiting."; exit 1; }
}

# Function to create Frigate configuration file with detector type
create_frigate_config() {
  load_configuration

  # Automatically set CONFIG_FOLDER to the script's directory
  CONFIG_FOLDER="$SCRIPT_DIR/config"
  echo "CONFIG_FOLDER=$CONFIG_FOLDER" >> "$SETTINGS_FILE"

  # Create the config folder if it doesn't exist
  mkdir -p "$CONFIG_FOLDER" || { echo "Error creating config folder. Exiting."; exit 1; }

  CONFIG_FILE="$CONFIG_FOLDER/config.yml"

  cat <<EOF > "$CONFIG_FILE"

mqtt:
  enabled: false  # Set this to true if you want to use MQTT
  host: mqtt.server.com
  user: mqtt_user
  password: password

detectors:
  cpu1:
    type: cpu
    num_threads: 3

objects:
  # Optional: list of objects to track from labelmap.txt (default: shown below)
  track:
  - person

cameras:
  Balcon:
    ui:
      order: 1
    ffmpeg:
      inputs:
      - path: rtsp://username:password@192.168.0.5:554/h264Preview_01_sub
        roles:
        - detect
      - path: rtsp://username:password@192.168.0.5:554/h264Preview_01_main
        roles:
        - record
    detect:
      width: 640
      height: 360
      fps: 7

EOF
}

# Function to start Frigate container
start_frigate_container() {
  load_configuration

  echo "Running Frigate NVR container..."

  # Check if the container already exists
  if docker ps -a --format '{{.Names}}' | grep -q '^frigate$'; then
    # Check if the container is running
    if docker ps --format '{{.Names}}' | grep -q '^frigate$'; then
      echo "Frigate container is already running."
      exit 1
    fi

    echo "Starting existing Frigate container..."
    docker start frigate &>/dev/null
    echo "Existing Frigate container started."
  else
    # Container does not exist, create and start a new one

    DOCKER_RUN_COMMAND="docker run -d \
      --name frigate \
      --restart always \
      --mount type=tmpfs,target=/tmp/cache,tmpfs-size=8000000000 \
      -p 5000:5000 \
      -p 1935:1935 \
      -p 8554:8554 \
      -p 8555:8555/udp \
      -v \"$SCRIPT_DIR/config\":/config \
      -v \"$SCRIPT_DIR/media\":/media \
      -e FRIGATE_RTSP_PASSWORD=\"$RTSP_PASSWORD\""

    # Check if an NVIDIA GPU will be used
    if [ "$USE_GPU" = true ]; then
      DOCKER_RUN_COMMAND="$DOCKER_RUN_COMMAND \
        --gpus all \
        -e NVIDIA_VISIBLE_DEVICES=all \
        -e NVIDIA_DRIVER_CAPABILITIES=compute,video,utility"
    fi

    # Check if a Coral USB device will be used
    if [ "$USE_CORAL" = true ]; then
      DOCKER_RUN_COMMAND="$DOCKER_RUN_COMMAND \
        --device /dev/bus/usb:/dev/bus/usb"
    fi

    DOCKER_RUN_COMMAND="$DOCKER_RUN_COMMAND \
      --shm-size=1000m \
      \"$FRIGATE_IMAGE\""

    # Execute the Docker run command
    eval "$DOCKER_RUN_COMMAND" || { echo "Error starting Frigate container. Exiting."; exit 1; }

    echo "Frigate NVR setup completed!"
    IP_ADDRESS=$(hostname -I | cut -d ' ' -f1)
    echo "Frigate container is running and ready to stream RTSP feeds. Access the Frigate web interface at http://localhost:5000"
    echo "Press Enter to continue..."
    read -r
  fi
}

# Main function
main() {
  check_docker
  check_dependencies
  load_configuration

  # Check if the command provided is 'start'
  if [ "$1" == "start" ]; then
    if [ -f "$SETTINGS_FILE" ]; then
      echo "Using configuration from $SETTINGS_FILE."
    else
      echo "No existing configuration file found. Prompting for configuration..."
      get_frigate_version
      prompt_for_media_folder
      prompt_for_gpu
      prompt_for_coral
    fi

    pull_frigate_image
    create_frigate_config
    start_frigate_container
    echo "Frigate installation and configuration completed!"
    IP_ADDRESS=$(hostname -I | cut -d ' ' -f1)
    echo "Access the Frigate web interface at http://$IP_ADDRESS:5000"
  elif [ "$1" == "stop" ]; then
    stop_frigate_container
  elif [ "$1" == "delete" ]; then
    delete_frigate_installation
  else
    echo "Usage: $0 {start|stop|delete}"
    exit 1
  fi
}

# Run the main function with the provided command-line argument
main "$1"

