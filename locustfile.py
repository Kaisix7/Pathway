import random
import uuid
from locust import HttpUser, task, between

class PathwayPerformanceUser(HttpUser):
    wait_time = between(1, 2)
    token = None
    email = None

    def on_start(self):
        # Register a unique user for this session
        self.email = f"perf_{uuid.uuid4().hex[:8]}@example.com"
        password = "Password123!"
        name = "Performance Tester"

        # Register user
        register_payload = {
            "name": name,
            "email": self.email,
            "password": password,
            "role": "user",
            "captcha_token": "dev_bypass"
        }
        self.client.post("/api/register/", json=register_payload)

        # Login to obtain JWT token
        login_payload = {
            "email": self.email,
            "password": password
        }
        response = self.client.post("/api/login/", json=login_payload)
        if response.status_code == 200:
            data = response.json()
            self.token = data.get("token")

    @task(3)
    def health_check(self):
        # Task 1: Check application health
        self.client.get("/health/")

    @task(2)
    def get_orders(self):
        # Task 2: Fetch list of orders
        headers = {"Authorization": f"Bearer {self.token}"} if self.token else {}
        self.client.get("/api/orders/", headers=headers)

    @task(1)
    def create_order(self):
        # Task 3: Create a new order
        headers = {"Authorization": f"Bearer {self.token}"} if self.token else {}
        order_payload = {
            "name": "Jane Doe",
            "tariff": "Standard",
            "price": 150,
            "service_type": "airport",
            "pickup_location": "Airport Terminal 1",
            "destination": "Grand Hotel",
            "user_email": self.email or "guest@example.com"
        }
        self.client.post("/api/orders/", json=order_payload, headers=headers)
