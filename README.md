# Pathway 

Pathway is a mobile application built with Flutter and Django that simplifies various user services such as visa applications, service requests, and user assistance.
## 📱 Features
* User registration
* Order creation (e.g., airport pickup services)
* View and manage orders
* Backend integration via Django REST API
* Multi-screen navigation (Home, Services, Visa, Assistant, Account)
## 🧱 Tech Stack
### Frontend
* Flutter (Dart)
### Backend
* Django (Python)
* JWT Authentication
* RBAC (Role-Based Access Control)
* CAPTCHA protection
* Google OAuth 2.0
### Infrastructure
* Docker
* PostgreSQL
* Render (deployment)
## Getting Started
### 1. Clone the repository
```bash
git clone https://github.com/Kaisix7/Pathway.git
cd Pathway
```
### 2. Run Backend (Django)
```bash
cd backend
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
python manage.py migrate
python manage.py runserver
```
### 3. Run Frontend (Flutter)

```bash
flutter pub get
flutter run
```
## API

Base URL:

```
http://127.0.0.1:8000/api
```

For Android Emulator:

```
http://10.0.2.2:8000/api
```
## Test
* test_register
* test_login
* test_orders
* test_admin_access
* test_rate_limit
* test_captcha
* test_2fa

Run tests:

```bash
pytest
```
##  Deployment
* Render
* Docker
## Author
Karina
## System docs
- `docs/ARCHITECTURE.md`
- `docs/DEPLOYMENT.md`
- `docs/GIT_WORKFLOW.md`
- `docs/BACKUPS.md`
