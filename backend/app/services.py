from sqlalchemy import select
from sqlalchemy.orm import Session

from app.models import Meeting
from app.schemas import MeetingCreate


def list_meetings(session: Session):
    return session.scalars(select(Meeting).order_by(Meeting.starts_at, Meeting.id)).all()


def create_meeting(session: Session, data: MeetingCreate):
    meeting = Meeting(**data.model_dump())
    session.add(meeting)
    session.commit()
    session.refresh(meeting)
    return meeting
