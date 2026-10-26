from sqlalchemy import select
from sqlalchemy.orm import Session

from app.models import Meeting
from app.schemas import AgendaSave, MeetingCreate


def list_meetings(session: Session):
    return session.scalars(select(Meeting).order_by(Meeting.starts_at, Meeting.id)).all()


def create_meeting(session: Session, data: MeetingCreate):
    meeting = Meeting(**data.model_dump())
    session.add(meeting)
    session.commit()
    session.refresh(meeting)
    return meeting


def save_agenda(session: Session, meeting_id, data: AgendaSave):
    meeting = session.get(Meeting, meeting_id)
    if meeting is None:
        return None
    meeting.agenda = data.model_dump(mode="json", include={"items", "action_items"})
    suggestion = data.ai_suggestion
    meeting.ai_suggestion = suggestion.model_dump(mode="json") if suggestion else None
    session.commit()
    session.refresh(meeting)
    return meeting
