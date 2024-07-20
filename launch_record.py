#!/usr/bin/python
import RPi.GPIO as GPIO
import time
import subprocess
import os
import signal

# Configuration
BUTTON_PIN = 12
LED_PIN = 25
RUNNING = False
record_process = None

# Set GPIO mode to GPIO.BOARD
GPIO.setmode(GPIO.BOARD)

# Set up the GPIO pins
GPIO.setup(BUTTON_PIN, GPIO.IN, pull_up_down=GPIO.PUD_UP)
GPIO.setup(LED_PIN, GPIO.OUT)

# Define a function to start recording
def start_recording(channel):
    global RUNNING, record_process
    if not RUNNING:
        RUNNING = True
        GPIO.output(LED_PIN, GPIO.HIGH)
        record_process = subprocess.Popen(['./new_record.sh'], preexec_fn=os.setsid)
        print("Recording started")

# Define a function to stop recording
def stop_recording(channel):
    global RUNNING, record_process
    if RUNNING:
        RUNNING = False
        GPIO.output(LED_PIN, GPIO.LOW)
        if record_process:
            os.killpg(os.getpgid(record_process.pid), signal.SIGINT)
            record_process.wait()
            print("Recording stopped")

# Add event detection for the button press
GPIO.add_event_detect(BUTTON_PIN, GPIO.FALLING, callback=start_recording, bouncetime=300)
GPIO.add_event_detect(BUTTON_PIN, GPIO.RISING, callback=stop_recording, bouncetime=300)

# Define a function to handle signals
def signal_handler(sig, frame):
    if RUNNING:
        stop_recording(None)
    GPIO.cleanup()
    exit(0)

signal.signal(signal.SIGINT, signal_handler)

print("Waiting for button press...")
try:
    while True:
        time.sleep(1)
except KeyboardInterrupt:
    GPIO.cleanup()
