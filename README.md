# Your Drive 🚀

**Your Drive** is a high-performance, cross-platform cloud storage application inspired by Google Drive, uniquely powered by **Telegram's MTProto API** for secure, scalable, and virtually unlimited file storage. 

By leveraging Telegram's robust infrastructure via `Telethon` on the backend, alongside a modern **Flutter** frontend, Your Drive delivers a seamless, secure, and fast file management experience.

---

## 🏗 System Architecture

The project is split into several standalone components to ensure maximum scalability and maintainability:

- 📱 **`frontend/your_drive`**: The core cross-platform client application built with **Flutter**. Handles user interactions, file picking, secure authentication (via Supabase), local caching, media playback, and UI.
- ⚙️ **`backend`**: A high-performance REST API built with **FastAPI** (Python). Acts as the bridge between the frontend and Telegram's servers. Uses **Telethon** for chunked file processing, MTProto communication, and Redis for caching.
- 🤖 **`NotifierBot`**: A dedicated Python automation bot that manages notifications, task updates, and acts as a bridge for user alerts.
- 🌐 **`website`**: The official landing page and web presence for Your Drive.
- 🛡️ **`admin`**: The administrative web panel/app for monitoring analytics, server health, and platform usage.

---

## 🛠 Tech Stack

### Frontend (Flutter App)
- **Framework:** Flutter (Dart)
- **Authentication:** Supabase, Google Sign-In, Local Auth (Biometrics)
- **Networking:** Dio, HTTP
- **Local Storage System:** Hive, Flutter Secure Storage, SQLite
- **Media & UI:** Video Player, File Picker, Photo View, PDF View, Material Design.

### Backend (API layer)
- **Framework:** FastAPI (Python)
- **Core Engine:** Telethon (MTProto API), Cryptg (for speed optimization)
- **Database / Caching:** Redis, SQLite (`files.db`)
- **Security:** Passlib (Bcrypt), Python-JOSE (Cryptography)

### Automation (NotifierBot)
- Python integration scripts (`bot_bridge.py`) for system events.

---

## ✨ Key Features

- **Unlimited Cloud Storage:** Bypasses conventional storage limits by acting as a distributed wrapper over Telegram’s servers.
- **High-Speed Chunked Uploads:** Custom backend implementations allowing fast streaming of large files.
- **Secure Authentication:** Multi-layered security including Supabase authentication and App-level local biometrics.
- **Media Previews:** Built-in PDF reader, high-quality photo viewer, and smooth video playback module.
- **Push Notifications:** Instant file processing updates via Firebase Cloud Messaging and Telegram bot bridges.

---

## 🚀 Getting Started

### Prerequisites

Ensure you have the following installed on your local machine:
- [Flutter SDK](https://flutter.dev/docs/get-started/install) (>=3.0.0 <4.0.0)
- [Python](https://www.python.org/downloads/) 3.10+
- [Redis](https://redis.io/download) Server

### 1. Backend Setup
1. Navigate to the backend folder: `cd backend`
2. Create a virtual environment: `python -m venv venv`
3. Activate the virtual environment, then install dependencies:
   ```bash
   pip install -r requirements.txt
   ```
4. Copy the environment template and fill in your Telegram API identifiers:
   ```bash
   cp .env.example .env
   ```
5. Start the FastAPI server:
   ```bash
   uvicorn app.main:app --reload
   ```

### 2. Frontend Setup
1. Navigate to the frontend directory: `cd frontend/your_drive`
2. Install Flutter packages:
   ```bash
   flutter pub get
   ```
3. Run the application:
   ```bash
   flutter run
   ```

### 3. Notifier Bot Setup
1. Navigate to the bot directory: `cd NotifierBot`
2. Create and activate a virtual environment.
3. Install dependencies: `pip install -r requirements.txt`
4. Run the script: `python bot_bridge.py`

---

## 🤝 Contributing
Contributions, issues, and feature requests are welcome!

## 📝 License
This project is proprietary or licensed under your chosen Open Source license.
