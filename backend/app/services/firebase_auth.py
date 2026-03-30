"""
Firebase Admin SDK — verify phone auth ID tokens.

Setup (one-time):
  1. Go to console.firebase.google.com → your project
  2. Project Settings → Service Accounts → Generate new private key
  3. Save the JSON file as backend/firebase-service-account.json
  4. Set FIREBASE_PROJECT_ID in backend/.env

The service account file is gitignored — never commit it.
"""

import json
import logging
import os

import firebase_admin
from firebase_admin import auth as firebase_auth, credentials

from app.core.config import settings

logger = logging.getLogger(__name__)

_initialized = False


def _init_firebase():
    global _initialized
    if _initialized or firebase_admin._apps:
        _initialized = True
        return

    service_account_path = settings.FIREBASE_SERVICE_ACCOUNT_PATH

    if os.path.exists(service_account_path):
        cred = credentials.Certificate(service_account_path)
        firebase_admin.initialize_app(cred)
        logger.info("Firebase Admin initialized from %s", service_account_path)
    elif settings.FIREBASE_SERVICE_ACCOUNT_JSON:
        # Fallback: JSON string stored directly in env var
        sa_dict = json.loads(settings.FIREBASE_SERVICE_ACCOUNT_JSON)
        cred = credentials.Certificate(sa_dict)
        firebase_admin.initialize_app(cred)
        logger.info("Firebase Admin initialized from env JSON")
    else:
        raise RuntimeError(
            "Firebase not configured. "
            f"Place firebase-service-account.json at {service_account_path} "
            "or set FIREBASE_SERVICE_ACCOUNT_JSON in backend/.env"
        )

    _initialized = True


class FirebaseAuthError(Exception):
    pass


def verify_firebase_token(id_token: str) -> dict:
    """
    Verify a Firebase ID token (from phone auth) and return user info.

    Returns:
        {
            "firebase_uid": "abc123",
            "phone_number": "+12125551234",
        }

    Raises:
        FirebaseAuthError if the token is invalid or expired.
    """
    try:
        _init_firebase()
    except RuntimeError as e:
        raise FirebaseAuthError(str(e))

    try:
        decoded = firebase_auth.verify_id_token(id_token)
    except firebase_auth.ExpiredIdTokenError:
        raise FirebaseAuthError("Firebase token has expired. Please sign in again.")
    except firebase_auth.InvalidIdTokenError as e:
        raise FirebaseAuthError(f"Invalid Firebase token: {e}")
    except Exception as e:
        raise FirebaseAuthError(f"Firebase verification failed: {e}")

    phone = decoded.get("phone_number")
    if not phone:
        raise FirebaseAuthError("No phone number in Firebase token. Ensure phone auth is used.")

    return {
        "firebase_uid": decoded["uid"],
        "phone_number": phone,
    }
