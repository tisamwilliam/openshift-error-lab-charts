from flask import Flask
import random, time

app = Flask(__name__)

@app.route("/actuator/health")
def health():
    # 模擬隨機延遲：30% 機率超過 5 秒
    if random.random() < 0.3:
        time.sleep(5)
    return {"status": "UP"}

@app.route("/")
def index():
    return "Order Service is running!"

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=8080)