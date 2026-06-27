from typing import Annotated

from fastapi import Depends
from sqlalchemy.ext.asyncio import AsyncSession

from app.database import get_db

# Авторизация вырезана (тестовый проект без пользователей) — эндпоинты публичные.
DbSession = Annotated[AsyncSession, Depends(get_db)]
