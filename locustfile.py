import uuid
from locust import HttpUser, task, between

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
            headers["Authorization"] = f"Token {self.token}"
            
        with self.client.get(
            f"/api/checkout/?user_email={self.email}",
            headers=headers,
            catch_response=True
        ) as response:
            # We catch response because Stripe keys might not be configured in the test environment,
            # but we want to make sure the endpoint responds properly (200, 302/303 redirect, or even 500 STRIPE ERROR if Stripe key is missing - which is expected in sandbox without keys).
            if response.status_code in [200, 302, 303]:
                response.success()
            elif response.status_code == 500 and "NO STRIPE KEY" in response.text:
                # Bypassing missing stripe key errors during load test
                response.success()
            else:
                response.failure(f"Checkout error: {response.text}")
