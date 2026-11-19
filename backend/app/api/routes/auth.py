"""
Phone authentication via Firebase.

Flow:
  1. Mobile uses Firebase SDK (expo-firebase-recaptcha) to verify phone + OTP
  2. Firebase returns an ID token
  3. Mobile sends the ID token to POST /auth/phone
  4. Backend verifies with Firebase Admin SDK → find/create user → return JWT

New users: is_new_user=True, full_name=None → mobile shows ProfileSetupScreen
Returning users: is_new_user=False, full_name set → mobile goes straight to home
"""

import logging

from fastapi import APIRouter, Depends, HTTPException, status
from pydantic import BaseModel, Field
from app.services import storage
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select

from app.core.database import get_db
from app.core.security import create_access_token
from app.models.user import User
from app.schemas.user import TokenResponse, UserResponse
from app.services.firebase_auth import verify_firebase_token, FirebaseAuthError
from app.api.deps import get_current_user

logger = logging.getLogger(__name__)
router = APIRouter()


class PhoneLoginRequest(BaseModel):
    firebase_token: str  # ID token from Firebase phone auth


class ProfileUpdateRequest(BaseModel):
    full_name: str | None = Field(None, max_length=80)
    avatar_url: str | None = None


@router.post("/phone", response_model=TokenResponse)
async def phone_login(
    payload: PhoneLoginRequest,
    db: AsyncSession = Depends(get_db),
):
    """
    Verify a Firebase phone auth ID token and return a ClosetEye JWT + user.
    Creates the user automatically on first sign-in.
    """
    try:
        info = verify_firebase_token(payload.firebase_token)
    except FirebaseAuthError as e:
        logger.warning("Firebase auth failed: %s", e)
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="We couldn't verify your sign in. Please try again.",
        )

    firebase_uid   = info["firebase_uid"]
    phone_number   = info["phone_number"]

    try:
        # Find existing user by firebase_uid
        result = await db.execute(select(User).where(User.firebase_uid == firebase_uid))
        user = result.scalar_one_or_none()
        is_new = False

        if not user:
            # Check if phone number exists under a different uid (shouldn't happen, but safe)
            result2 = await db.execute(select(User).where(User.phone_number == phone_number))
            user = result2.scalar_one_or_none()
            if user:
                user.firebase_uid = firebase_uid  # update uid
            else:
                user = User(phone_number=phone_number, firebase_uid=firebase_uid)
                db.add(user)
                is_new = True

            await db.commit()
            await db.refresh(user)

    except Exception:
        logger.exception("Database error in phone_login")
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Something went wrong signing you in. Please try again.",
        )

    token = create_access_token(subject=str(user.id))
    logger.info("Phone login: user=%s new=%s", user.id, is_new)

    return TokenResponse(
        access_token=token,
        is_new_user=is_new,
        user=UserResponse.model_validate(user),
    )


@router.patch("/profile", response_model=UserResponse)
async def update_profile(
    payload: ProfileUpdateRequest,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """
    Update the authenticated user's profile (full_name, avatar_url).
    Called after new-user onboarding on the ProfileSetupScreen.
    """
    if payload.full_name is not None:
        current_user.full_name = payload.full_name
    if payload.avatar_url is not None:
        # Only the user's own uploaded files; never arbitrary external URLs.
        current_user.avatar_url = storage.normalize_owned(payload.avatar_url, current_user.id)

    try:
        await db.commit()
        await db.refresh(current_user)
    except Exception:
        logger.exception("Database error updating profile")
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Couldn't save your profile. Please try again.",
        )
    return UserResponse.model_validate(current_user)
