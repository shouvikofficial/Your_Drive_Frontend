class Env {
  // 🔁 change this only
  static const bool isDev = false;

  // 🔥 backend URL switch
  static const String backendBaseUrl = isDev
      ? "http://10.0.2.2:8000"// ✅ LOCAL FastAPI
      : "https://your-drive-backend.onrender.com"; // 🌍 Render

  // ⚡ Supabase Configuration (Added these lines)
  static const String supabaseUrl = 'https://knzogkwgczsnfaypokto.supabase.co';
  static const String supabaseAnonKey = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Imtuem9na3dnY3pzbmZheXBva3RvIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzAyMTUzNjEsImV4cCI6MjA4NTc5MTM2MX0.i-aHu3ZcbtN2WPgLl8nvY6m5fhKgeNlwnZt-QMwRQFg';
}