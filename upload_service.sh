#!/bin/bash

# Load the configuration
source /home/crosstech/toughcam-logger/config/recording_uploading_settings.txt

# Set up gsutil authentication
echo "$(date +%Y-%m-%dT%H:%M:%S.%3N) - Starting gsutil authentication" | tee -a /home/crosstech/toughcam-logger/upload_service.log
gcloud auth activate-service-account auto-uploader@virbatim.iam.gserviceaccount.com --key-file=/home/crosstech/toughcam-logger/config/auto-uploader-key.json --project=virbatim
if [ $? -eq 0 ]; then
    echo "$(date +%Y-%m-%dT%H:%M:%S.%3N) - Successfully authenticated gsutil" | tee -a /home/crosstech/toughcam-logger/upload_service.log
else
    echo "$(date +%Y-%m-%dT%H:%M:%S.%3N) - Failed to authenticate gsutil" | tee -a /home/crosstech/toughcam-logger/upload_service.log
fi

# Function to upload files
upload_files() {
    echo "$(date +%Y-%m-%dT%H:%M:%S.%3N) - Checking for files to upload" | tee -a /home/crosstech/toughcam-logger/upload_service.log
    for file in "$OUTPUT_DIR"/*; do
        if [ -f "$file" ]; then
            echo "$(date +%Y-%m-%dT%H:%M:%S.%3N) - Found file: $file" | tee -a /home/crosstech/toughcam-logger/upload_service.log
            # Upload the file to Google Cloud Storage
            gsutil mv "$file" "gs://auto-uploads/$GCS_SUBFOLDER/"
            
            # Check if the upload was successful
            if [ $? -eq 0 ]; then
                echo "$(date +%Y-%m-%dT%H:%M:%S.%3N) - Successfully uploaded $file to gs://auto-uploads/$GCS_SUBFOLDER/" | tee -a /home/crosstech/toughcam-logger/upload_service.log
                rm -f "$file" # Delete the file after successful upload
            else
                echo "$(date +%Y-%m-%dT%H:%M:%S.%3N) - Failed to upload $file. Retrying..." | tee -a /home/crosstech/toughcam-logger/upload_service.log
                # Retry logic can be added here if needed
            fi
        else
            echo "$(date +%Y-%m-%dT%H:%M:%S.%3N) - No files found to upload" | tee -a /home/crosstech/toughcam-logger/upload_service.log
        fi
    done
}

# Run the upload_files function every minute
echo "$(date +%Y-%m-%dT%H:%M:%S.%3N) - Starting upload service loop" | tee -a /home/crosstech/toughcam-logger/upload_service.log
while true; do
    upload_files
    sleep 60 # Sleep for 60 seconds before checking again
done
