import time
import subprocess
import os
import signal
from gpiozero import Button, LED

BUTTON_PIN = 12
LED_PIN = 25
RUNNING = False
record_process = None

button = Button(BUTTON_PIN)
led = LED(LED_PIN)

def start_recording():
    global RUNNING, record_process
    if not RUNNING:
        RUNNING = True
        led.on()
        record_process = subprocess.Popen(['/home/crosstech/toughcam-logger/new_record.sh'], preexec_fn=os.setsid)
        print("Recording started")

def stop_recording():
    global RUNNING, record_process
    if RUNNING:
        RUNNING = False
        led.blink(on_time=0.5, off_time=0.5)
        if record_process:
            os.killpg(os.getpgid(record_process.pid), signal.SIGINT)
            record_process.wait()
            print("Recording stopped")
        led.off()

button.when_pressed = start_recording
button.when_released = stop_recording

def signal_handler(sig, frame):
    if RUNNING:
        stop_recording()
    exit(0)

signal.signal(signal.SIGINT, signal_handler)

print("Waiting for button press...")
while True:
    time.sleep(1)
