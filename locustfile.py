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

class PathwayUser(HttpUser):
    # Think time between tasks: 1 to 5 seconds
    wait_time = between(1, 5)

    def on_start(self):
        """Executed when a simulated user starts."""
        self.email = f"loadtest_{uuid.uuid4().hex[:8]}@example.com"
        self.password = "Secr3tP@ssw0rd!"
        self.name = "LoadTest User"
        self.token = None
        self.register()

    def register(self):
        """Register the simulated user."""
        with self.client.post(
            "/api/register/",
            json={
                "name": self.name,
                "email": self.email,
                "password": self.password,
                "captcha_token": "bypass", # Using our configured debug captcha bypass token
                "plan": "free",
                "role": "user"
            },
            catch_response=True
        ) as response:
            if response.status_code == 200:
                data = response.json()
                self.token = data.get("token")
            else:
                response.failure(f"Registration failed with code {response.status_code}: {response.text}")

    @task(3)
    def view_frontend(self):
        """Simulate loading the main page of the application."""
        self.client.get("/")

    @task(2)
    def check_health(self):
        """Simulate checking the service health status."""
        self.client.get("/api/health/")

    @task(1)
    def simulate_login(self):
        """Simulate user logging in."""
        with self.client.post(
            "/api/login/",
            json={
                "email": self.email,
                "password": self.password
            },
            catch_response=True
        ) as response:
            if response.status_code != 200:
                response.failure(f"Login failed: {response.text}")

    @task(1)
    def initiate_stripe_checkout(self):
        """Simulate user opening the Stripe checkout screen."""
        headers = {}
        if self.token:
            headers["Authorization"] = f"Bearer {self.token}"
            
        with self.client.get(
            f"/api/checkout/?user_email={self.email}",
            headers=headers,
            catch_response=True
        ) as response:
            if response.status_code in [200, 302, 303]:
                response.success()
            elif response.status_code == 500 and "NO STRIPE KEY" in response.text:
                response.success()
            else:
                response.failure(f"Checkout error: {response.text}")
