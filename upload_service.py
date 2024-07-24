import os
import time
import subprocess
import logging
from gpiozero import LED
from datetime import datetime

# Configuration file
CONFIG_FILE = "/home/crosstech/toughcam-release/config/config.txt"

# Parse the Toughcam ID from the configuration file
if not os.path.isfile(CONFIG_FILE):
    raise FileNotFoundError(f"Configuration file not found at {CONFIG_FILE}")

with open(CONFIG_FILE, 'r') as file:
    lines = file.readlines()

TOUGHCAM_ID = None
for line in lines:
    if line.startswith("TOUGHCAM_ID="):
        TOUGHCAM_ID = line.strip().split("=")[1]
        break

if TOUGHCAM_ID is None:
    raise ValueError("Toughcam ID not found in configuration file")

# Configuration
OUTPUT_DIR = "/home/crosstech/toughcam-release/output_videos"
TEMP_DIR = "/home/crosstech/toughcam-release/temp_videos"
GCS_SUBFOLDER = TOUGHCAM_ID
LOG_FILE = "/home/crosstech/toughcam-release/upload_service.log"
LED_PIN = 18  # GPIO pin for the LED
RECORDING_SCRIPT_NAME = "recording_script.py"  # Name of the recording script

# Set up logging
logging.basicConfig(filename=LOG_FILE, level=logging.INFO, format='%(asctime)s - %(message)s')

# Set up LED
led = LED(LED_PIN)

def log_message(message):
    timestamp = datetime.now().strftime('%Y-%m-%dT%H:%M:%S.%3N')
    log_entry = f"{timestamp} - {message}"
    logging.info(log_entry)
    print(log_entry)

def authenticate_gsutil():
    log_message("Starting gsutil authentication")
    result = subprocess.run([
        'gcloud', 'auth', 'activate-service-account',
        'auto-uploader@virbatim.iam.gserviceaccount.com',
        '--key-file=/home/crosstech/toughcam-release/config/auto-uploader-key.json',
        '--project=virbatim'
    ], capture_output=True, text=True)
    if result.returncode == 0:
        log_message("Successfully authenticated gsutil")
    else:
        log_message(f"Failed to authenticate gsutil: {result.stderr}")

def upload_files():
    log_message("Checking for files to upload")
    files = os.listdir(OUTPUT_DIR)
    if not files:
        log_message("No files found to upload")
        return

    for file_name in files:
        file_path = os.path.join(OUTPUT_DIR, file_name)
        if os.path.isfile(file_path):
            log_message(f"Found file: {file_path}")
            result = subprocess.run(['gsutil', 'mv', file_path, f"gs://auto-uploads/{GCS_SUBFOLDER}/"], capture_output=True, text=True)
            if result.returncode == 0:
                log_message(f"Successfully uploaded {file_path} to gs://auto-uploads/{GCS_SUBFOLDER}/")
            else:
                log_message(f"Failed to upload {file_path}. Retrying... {result.stderr}")

def is_recording_script_running():
    result = subprocess.run(['pgrep', '-f', RECORDING_SCRIPT_NAME], capture_output=True, text=True)
    return result.returncode == 0

def main():
    authenticate_gsutil()
    log_message("Starting upload service loop")
    while True:
        upload_files()

        # Check if recording script is not running and temp_videos directory is empty
        if not is_recording_script_running() and not os.listdir(TEMP_DIR):
            led.on()
        else:
            led.off()

        time.sleep(1)

if __name__ == "__main__":
    main()
