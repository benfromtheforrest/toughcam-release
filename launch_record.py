import time
import subprocess
import os
import signal
from gpiozero import Button, LED
from datetime import datetime, timedelta

BUTTON_PIN = 12
LED_PIN = 25
DEBOUNCE_TIME = 0.3  # debounce time in seconds
DELAY_AFTER_STOP = 1  # delay time after stopping recording

RUNNING = False
record_process = None
last_press_time = datetime.min
last_stop_time = datetime.min

button = Button(BUTTON_PIN)
led = LED(LED_PIN)

def toggle_recording():
    global RUNNING, record_process, last_press_time, last_stop_time
    current_time = datetime.now()
    
    if current_time - last_press_time < timedelta(seconds=DEBOUNCE_TIME):
        return  # Ignore the press as it is within the debounce period

    if RUNNING:
        RUNNING = False
        led.blink(on_time=0.5, off_time=0.5)
        if record_process:
            os.killpg(os.getpgid(record_process.pid), signal.SIGINT)
            record_process.wait()
            print("Recording stopped")
        led.off()
        last_stop_time = current_time  # Update the last stop time
    else:
        if current_time - last_stop_time < timedelta(seconds=DELAY_AFTER_STOP):
            return  # Ignore the press if within the delay period after stopping
        RUNNING = True
        led.on()
        record_process = subprocess.Popen(['/home/crosstech/toughcam-release/new_record.sh'], preexec_fn=os.setsid)
        print("Recording started")
    
    last_press_time = current_time  # Update the last press time

button.when_pressed = toggle_recording

def signal_handler(sig, frame):
    global RUNNING, record_process
    if RUNNING:
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
