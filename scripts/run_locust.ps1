Write-Host "Starting Locust load test..."
locust -f locustfile.py --headless -u 100 -r 10 --run-time 2m --html locust_report.html --host http://localhost:8000
Write-Host "Load test complete. Report saved to locust_report.html."
