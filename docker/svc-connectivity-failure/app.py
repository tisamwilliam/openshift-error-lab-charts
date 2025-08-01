from flask import Flask
import random, time

app = Flask(__name__)

@app.route("/actuator/health")
def health():
    if random.random() < 0.5:
        time.sleep(5)
    return {"status": "UP"}

@app.route("/")
def index():
    return "Order Service is running!"

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=8080)