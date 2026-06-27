"""Создать администратора. Запуск: python -m scripts.create_admin <email> <password>."""

import asyncio
import sys

from sqlalchemy import select

from app.database import async_session_maker
from app.models import User
from app.security import hash_password


async def main(email: str, password: str) -> None:
    async with async_session_maker() as db:
        existing = await db.scalar(select(User).where(User.email == email))
        if existing:
            existing.is_admin = True
            existing.password_hash = hash_password(password)
            print(f"Updated existing user {email} -> admin")
        else:
            db.add(
                User(email=email, password_hash=hash_password(password), is_admin=True)
            )
            print(f"Created admin {email}")
        await db.commit()


if __name__ == "__main__":
    if len(sys.argv) != 3:
        print("Usage: python -m scripts.create_admin <email> <password>")
        sys.exit(1)
    asyncio.run(main(sys.argv[1], sys.argv[2]))
