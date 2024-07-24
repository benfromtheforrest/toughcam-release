#!/bin/bash

# Variables
DURATION=600   # Duration of each recording loop in seconds, this loop is then split into segments (size defined below) and uploaded
WIDTH=2304
HEIGHT=1296
FRAMERATE=56
BITRATE=10000000
SEGMENT_SIZE=100000000 # Segment size in bytes - 100MB default
TEMP_DIR="/home/crosstech/toughcam-release/temp_videos"
OUTPUT_DIR="/home/crosstech/toughcam-release/output_videos"
LOG_FILE="/home/crosstech/toughcam-release/video_processing.log"
GPS_DEVICE="/dev/ttyACM0"
GPS_BAUDRATE=38400
ENABLE_GPS_LOGGING=true  # Set to false to disable GPS logging
POWER_CYCLE_GPS=false  # Set to false to disable power cycling the GPS - can fix weird behaviour but adds 5 seconds downtime between record loops
RETRY_INTERVAL=5  # Interval (in seconds) to check for GPS device availability
GCS_BUCKET="gs://auto-uploads/tc001"  # Google Cloud Storage subfolder
HOSTNAME_PREFIX="tc001"
CAMERA_OPTION=0  # 0 for camera 0, 1 for camera 1, 2 for both cameras

# Path to the USB reset script
USB_RESET_SCRIPT="/home/crosstech/toughcam-release/reset_gps_usb.sh"

# Create directories if they don't exist
mkdir -p $TEMP_DIR
mkdir -p $OUTPUT_DIR

# Variables to hold process IDs
recording_pid0=0
recording_pid1=0
gps_pid=0
processing_pid0=0
processing_pid1=0
last_temp_filename0=""
last_temp_filename1=""
last_output_pattern0=""
last_output_pattern1=""
last_precise_start_time=""
last_specific_log_file=""

# Function to log timestamps with millisecond accuracy
log_time() {
    local event=$1
    local specific_log_file=$2
    echo "$(date +%Y-%m-%dT%H:%M:%S.%3N) - $event" | tee -a $LOG_FILE $specific_log_file
}

# Function to process video segments
process_segment() {
    local input_file=$1
    local output_pattern=$2
    local start_time=$3
    local specific_log_file=$4

    # Capture processing start time
    local processing_start_time=$(date +%s%3N)
    log_time "Processing started for $input_file" $specific_log_file

    gst-launch-1.0 filesrc location=$input_file ! qtdemux ! queue ! h264parse ! splitmuxsink location=$output_pattern max-size-bytes=$SEGMENT_SIZE

    # Capture processing end time
    local processing_end_time=$(date +%s%3N)
    log_time "Processing finished for $input_file" $specific_log_file

    # Calculate and print processing elapsed time
    local processing_elapsed_time=$((processing_end_time - processing_start_time))
    echo "Processing time for $input_file: $processing_elapsed_time ms" | tee -a $specific_log_file

    rm $input_file

    # Move log and GPS files to output directory
    mv "${specific_log_file}" "${OUTPUT_DIR}/$(basename "${specific_log_file}")"
    mv "${GPS_LOG_FILE}" "${OUTPUT_DIR}/$(basename "${GPS_LOG_FILE}")"
}

# Function to log GPS data with timestamps
log_gps_data() {
    local gps_log_file=$1

    # Wait for the GPS device to become available
    while [ ! -e $GPS_DEVICE ]; do
        echo "Waiting for GPS device $GPS_DEVICE to become available..."
        sleep $RETRY_INTERVAL
    done

    stty -F $GPS_DEVICE $GPS_BAUDRATE

    # Read GPS data line-by-line, add timestamp, and write to the log file
    {
        while read -r line; do
            echo "$(date +%Y-%m-%dT%H:%M:%S.%3N) $line"
        done < $GPS_DEVICE
    } > $gps_log_file &
    gps_pid=$!

    # Return the PID of the GPS logging process
    echo $gps_pid
}

# Function to power cycle the USB device without holding execution
power_cycle_usb() {
    echo "Power cycling USB device using $USB_RESET_SCRIPT"
    sudo $USB_RESET_SCRIPT &
}

# Graceful shutdown function
graceful_shutdown() {
    echo "Graceful shutdown initiated..."

    if (("$recording_pid0" != 0)); then
        kill -INT "$recording_pid0" 2>/dev/null
        wait "$recording_pid0" 2>/dev/null
    fi

    if (("$recording_pid1" != 0)); then
        kill -INT "$recording_pid1" 2>/dev/null
        wait "$recording_pid1" 2>/dev/null
    fi

    if (("$gps_pid" != 0)); then
        kill "$gps_pid" 2>/dev/null
        wait "$gps_pid" 2>/dev/null
    fi

    if [ "$CAMERA_OPTION" = 0 ] || [ "$CAMERA_OPTION" = 2 ]; then
        if [ -n "$last_temp_filename0" ]; then
            echo "Processing last video segment for camera 0..."
            process_segment "$last_temp_filename0" "$last_output_pattern0" "$last_precise_start_time" "$last_specific_log_file"
        else
            echo "No last video segment to process for camera 0."
        fi
    fi

    if [ "$CAMERA_OPTION" = 1 ] || [ "$CAMERA_OPTION" = 2 ]; then
        if [ -n "$last_temp_filename1" ]; then
            echo "Processing last video segment for camera 1..."
            process_segment "$last_temp_filename1" "$last_output_pattern1" "$last_precise_start_time" "$last_specific_log_file"
        else
            echo "No last video segment to process for camera 1."
        fi
    fi

    echo "Shutdown complete."
    exit 0
}

# Set trap to catch termination signals and call graceful_shutdown
trap graceful_shutdown SIGINT SIGTERM

# Record and process in parallel
segment_number=0
while true; do
    TIMESTAMP=$(date +%Y%m%d_%H%M%S)
    TEMP_FILENAME0="$TEMP_DIR/${HOSTNAME_PREFIX}_${TIMESTAMP}_cam0.mp4"
    TEMP_FILENAME1="$TEMP_DIR/${HOSTNAME_PREFIX}_${TIMESTAMP}_cam1.mp4"
    OUTPUT_PATTERN0="$OUTPUT_DIR/${HOSTNAME_PREFIX}_${TIMESTAMP}_cam0_segment_%05d.mp4"
    OUTPUT_PATTERN1="$OUTPUT_DIR/${HOSTNAME_PREFIX}_${TIMESTAMP}_cam1_segment_%05d.mp4"
    SPECIFIC_LOG_FILE="$TEMP_DIR/${HOSTNAME_PREFIX}_${TIMESTAMP}_log.log"
    GPS_LOG_FILE="$TEMP_DIR/${HOSTNAME_PREFIX}_${TIMESTAMP}_gps.log"
    segment_number=$((segment_number + 1))

    # Log the script start time
    log_time "Script started" $SPECIFIC_LOG_FILE

    # Power cycle the USB device if enabled
    if [ "$POWER_CYCLE_GPS" = true ]; then
        power_cycle_usb
        log_time "Power cycled the USB device" $SPECIFIC_LOG_FILE
    fi

    # Capture the precise start time before recording
    precise_start_time=$(date +%s%3N)
    log_time "Recording start time captured: $precise_start_time" $SPECIFIC_LOG_FILE

    if [ "$ENABLE_GPS_LOGGING" = true ]; then
        # Start logging GPS data
        gps_pid=$(log_gps_data $GPS_LOG_FILE)
        log_time "Started logging GPS data to $GPS_LOG_FILE" $SPECIFIC_LOG_FILE
    fi

    # Assign the variables before starting recording
    last_precise_start_time="$precise_start_time"
    last_specific_log_file="$SPECIFIC_LOG_FILE"

    # Record the video segment based on camera option
    if [ "$CAMERA_OPTION" = 0 ] || [ "$CAMERA_OPTION" = 2 ]; then
        echo "Starting Recording from camera 0..."
        libcamera-vid -t $((DURATION * 1000)) --height $HEIGHT --width $WIDTH --framerate $FRAMERATE --bitrate $BITRATE --hflip --vflip -o $TEMP_FILENAME0 2>&1 -v 0 &
        recording_pid0=$!
        last_temp_filename0="$TEMP_FILENAME0"
        last_output_pattern0="$OUTPUT_PATTERN0"
    fi

    if [ "$CAMERA_OPTION" = 1 ] || [ "$CAMERA_OPTION" = 2 ]; then
        echo "Starting Recording from camera 1..."
        libcamera-vid -t $((DURATION * 1000)) --height $HEIGHT --width $WIDTH --framerate $FRAMERATE --bitrate $BITRATE --hflip --vflip -o $TEMP_FILENAME1 --camera 1 2>&1 -v 0 &
        recording_pid1=$!
        last_temp_filename1="$TEMP_FILENAME1"
        last_output_pattern1="$OUTPUT_PATTERN1"
    fi

    # Wait for recording to finish
    if [ "$CAMERA_OPTION" = 0 ] || [ "$CAMERA_OPTION" = 2 ]; then
        wait $recording_pid0
        recording_pid0=0
    fi

    if [ "$CAMERA_OPTION" = 1 ] || [ "$CAMERA_OPTION" = 2 ]; then
        wait $recording_pid1
        recording_pid1=0
    fi

    # Log the recording end time
    recording_end_time=$(date +%s%3N)
    log_time "Recording ended: $recording_end_time" $SPECIFIC_LOG_FILE

    if [ "$ENABLE_GPS_LOGGING" = true ]; then
        # Stop logging GPS data
        kill $gps_pid
        wait $gps_pid
        log_time "Stopped logging GPS data" $SPECIFIC_LOG_FILE
    fi

    # Detect when the file is created in the filesystem
    if [ "$CAMERA_OPTION" = 0 ] || [ "$CAMERA_OPTION" = 2 ]; then
        while [ ! -f "$TEMP_FILENAME0" ]; do
            sleep 0.001
        done
        file_detect_time0=$(date +%s%3N)
        log_time "File detected in filesystem: $TEMP_FILENAME0 at $file_detect_time0" $SPECIFIC_LOG_FILE

        # Process the recorded segment for camera 0
        process_segment "$TEMP_FILENAME0" "$OUTPUT_PATTERN0" "$precise_start_time" "$SPECIFIC_LOG_FILE" &
        processing_pid0=$!
    fi

    if [ "$CAMERA_OPTION" = 1 ] || [ "$CAMERA_OPTION" = 2 ]; then
        while [ ! -f "$TEMP_FILENAME1" ]; do
            sleep 0.001
        done
        file_detect_time1=$(date +%s%3N)
        log_time "File detected in filesystem: $TEMP_FILENAME1 at $file_detect_time1" $SPECIFIC_LOG_FILE

        # Process the recorded segment for camera 1
        process_segment "$TEMP_FILENAME1" "$OUTPUT_PATTERN1" "$precise_start_time" "$SPECIFIC_LOG_FILE" &
        processing_pid1=$!
    fi
done
