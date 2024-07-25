import time
import subprocess
import os
import signal
from gpiozero import Button, LED
from datetime import datetime, timedelta

BUTTON_PIN = 12
LED_PIN = 25
DEBOUNCE_TIME = 0.3  # debounce time in seconds
DELAY_AFTER_STOP = 5  # delay time after stopping recording
MIN_RECORDING_TIME = 5  # minimum recording time in seconds

RUNNING = False
record_process = None
last_press_time = datetime.min
last_stop_time = datetime.min
start_time = datetime.min

button = Button(BUTTON_PIN)
led = LED(LED_PIN)

def toggle_recording():
    global RUNNING, record_process, last_press_time, last_stop_time, start_time
    current_time = datetime.now()
    
    print(f"Button pressed at {current_time}")
    print(f"Time since last press: {current_time - last_press_time}")
    print(f"Time since last stop: {current_time - last_stop_time}")
    
    if current_time - last_press_time < timedelta(seconds=DEBOUNCE_TIME):
        print(f"Ignoring press within debounce period: {current_time - last_press_time}")
        return  # Ignore the press as it is within the debounce period

    if RUNNING:
        if current_time - start_time < timedelta(seconds=MIN_RECORDING_TIME):
            print(f"Ignoring press within minimum recording time: {current_time - start_time}")
            return  # Ignore the press as it is within the minimum recording time
        print("Stopping recording...")
        RUNNING = False
        led.blink(on_time=0.5, off_time=0.5)
        if record_process:
            os.killpg(os.getpgid(record_process.pid), signal.SIGINT)
            record_process.wait()
            print("Recording stopped")
        led.off()
        last_stop_time = current_time  # Update the last stop time
        print(f"Recording stopped at {last_stop_time}")
    else:
        if current_time - last_stop_time < timedelta(seconds=DELAY_AFTER_STOP):
            print(f"Ignoring press within delay period after stopping: {current_time - last_stop_time}")
            return  # Ignore the press if within the delay period after stopping
        print("Starting recording...")
        RUNNING = True
        led.on()
        record_process = subprocess.Popen(['/home/crosstech/toughcam-release/new_record.sh'], preexec_fn=os.setsid)
        start_time = current_time  # Update the start time
        print("Recording started")
    
    last_press_time = current_time  # Update the last press time
    print(f"Last press time updated to {last_press_time}")

button.when_pressed = toggle_recording

def signal_handler(sig, frame):
    global RUNNING, record_process
    if RUNNING:
        print("Signal received, stopping recording...")
        RUNNING = False
        if record_process:
            os.killpg(os.getpgid(record_process.pid), signal.SIGINT)
            record_process.wait()
        led.off()
    exit(0)

signal.signal(signal.SIGINT, signal_handler)

print("Waiting for button press...")
while True:
    time.sleep(1)
