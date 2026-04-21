"""
app.py
AI-Powered QA Automation System — Flask application entry point.

Usage:
    python app.py

The app will automatically open http://localhost:5000 in your default browser.
"""

import os
import threading
import webbrowser

from flask import Flask, render_template, send_from_directory
from flask_cors import CORS

import config

# ─── Import route blueprints ─────────────────────────────────
from routes.generate import generate_bp
from routes.run_tests import run_tests_bp
from routes.stream import stream_bp
from routes.reports import reports_bp
from routes.jira import jira_bp


def create_app() -> Flask:
    """Create, configure, and return the Flask application."""
    app = Flask(
        __name__,
        template_folder="templates",
        static_folder="static",
    )

    # Basic configuration
    app.config["SECRET_KEY"] = config.SECRET_KEY
    app.config["MAX_CONTENT_LENGTH"] = 32 * 1024 * 1024  # 32 MB

    # Allow cross-origin requests (useful when API calls are made from the browser)
    CORS(app)

    # ── Register blueprints ────────────────────────────────────
    app.register_blueprint(generate_bp,  url_prefix="/api")
    app.register_blueprint(run_tests_bp, url_prefix="/api")
    app.register_blueprint(stream_bp,    url_prefix="/api")
    app.register_blueprint(reports_bp,   url_prefix="/api")
    app.register_blueprint(jira_bp,      url_prefix="/api/jira")

    # ── Serve Allure HTML report (static files) ────────────────
    @app.route("/allure-report/")
    @app.route("/allure-report/<path:filename>")
    def allure_report(filename: str = "index.html"):
        report_dir = os.path.join(os.path.dirname(__file__), "reports", "allure-report")
        return send_from_directory(report_dir, filename)

    # Redirect /allure-report (no slash) to /allure-report/ so relative paths work
    @app.route("/allure-report")
    def allure_report_redirect():
        from flask import redirect
        return redirect("/allure-report/", code=301)

    # ── Serve RF run reports ───────────────────────────────────
    @app.route("/run-report/<run_id>/<path:filename>")
    def run_report(run_id: str, filename: str):
        run_dir = os.path.join(config.RF_OUTPUT_DIR, run_id)
        return send_from_directory(run_dir, filename)

    # ── Main UI ────────────────────────────────────────────────
    @app.route("/")
    def index():
        return render_template("index.html")

    return app


def _open_browser():
    """Open the system browser after a short startup delay."""
    import time
    time.sleep(1.8)
    webbrowser.open(f"http://localhost:{config.PORT}")


def _ensure_dirs():
    """Create all required output directories."""
    dirs = [
        config.RF_SCRIPTS_DIR,
        config.RF_OUTPUT_DIR,
        config.RF_ALLURE_RESULTS,
        config.RF_ALLURE_REPORT,
        config.RF_SCREENSHOTS_DIR,
        os.path.join(os.path.dirname(__file__), "reports"),
    ]
    for d in dirs:
        os.makedirs(d, exist_ok=True)


if __name__ == "__main__":
    _ensure_dirs()

    # Launch browser in a daemon thread so it doesn't block startup
    t = threading.Thread(target=_open_browser, daemon=True)
    t.start()

    app = create_app()
    print("=" * 60)
    print(" AI-Powered QA Automation System")
    print(f" Running at: http://localhost:{config.PORT}")
    print("=" * 60)
    app.run(
        host="0.0.0.0",
        port=config.PORT,
        debug=config.DEBUG,
        threaded=True,
        use_reloader=False,   # Disable reloader to prevent double browser open
    )
