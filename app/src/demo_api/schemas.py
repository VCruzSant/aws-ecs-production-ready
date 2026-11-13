from datetime import datetime
from typing import Annotated

from pydantic import BaseModel, ConfigDict, Field

Title = Annotated[str, Field(min_length=1, max_length=200)]


class TaskCreate(BaseModel):
    title: Title
    done: bool = False


class TaskUpdate(BaseModel):
    title: Title | None = None
    done: bool | None = None


class TaskRead(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: int
    title: str
    done: bool
    created_at: datetime
