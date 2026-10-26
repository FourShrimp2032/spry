"""The contract between the agenda parser and the rest of Spry. No AWS, no model here."""

from datetime import date, datetime

from pydantic import BaseModel, Field, field_validator


class AgendaItem(BaseModel):
    topic: str = Field(min_length=1, max_length=300)
    owner: str | None = Field(default=None, max_length=200)  # a name or an email, as written
    minutes: int | None = Field(default=None, ge=1, le=480)


class ActionItem(BaseModel):
    task: str = Field(min_length=1, max_length=500)
    owner: str | None = Field(default=None, max_length=200)
    due: date | None = None


class ParsedAgenda(BaseModel):
    title: str | None = Field(default=None, max_length=200)
    starts_at: str | None = None  # ISO 8601 with the user's offset, if the text says when
    duration_minutes: int | None = Field(default=None, ge=1, le=600)
    items: list[AgendaItem]
    action_items: list[ActionItem] = []
    language: str = Field(min_length=2, max_length=10)  # "uk", "en", ...

    @field_validator("starts_at")
    @classmethod
    def offset_required(cls, value):
        # "10:00" without an offset is ambiguous across time zones; make the model say which.
        if value is not None and datetime.fromisoformat(value).tzinfo is None:
            raise ValueError("starts_at needs a UTC offset, e.g. 2026-10-26T10:00:00+02:00")
        return value
