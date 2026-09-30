from datetime import UTC
from typing import Annotated
from uuid import UUID

from pydantic import AwareDatetime, BaseModel, ConfigDict, Field, field_validator, model_validator


class MeetingCreate(BaseModel):
    model_config = ConfigDict(extra="forbid", str_strip_whitespace=True)
    title: str = Field(min_length=1, max_length=200)
    starts_at: AwareDatetime
    ends_at: AwareDatetime
    attendee_count: Annotated[int, Field(strict=True, ge=0, le=2147483647)]

    @field_validator("starts_at", "ends_at", mode="before")
    @classmethod
    def require_iso_string(cls, value):
        if not isinstance(value, str):
            raise ValueError("Use an RFC3339 date string with timezone")
        return value

    @field_validator("starts_at", "ends_at")
    @classmethod
    def normalize_utc(cls, value):
        return value.astimezone(UTC)

    @model_validator(mode="after")
    def check_duration(self):
        if self.ends_at <= self.starts_at:
            raise ValueError("ends_at must be later than starts_at")
        return self


class MeetingRead(BaseModel):
    model_config = ConfigDict(from_attributes=True)
    id: UUID
    title: str
    starts_at: AwareDatetime
    ends_at: AwareDatetime
    attendee_count: int

    @field_validator("starts_at", "ends_at")
    @classmethod
    def normalize_utc(cls, value):
        return value.astimezone(UTC)
