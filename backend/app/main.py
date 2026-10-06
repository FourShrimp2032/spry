import os

from fastapi import Depends, FastAPI
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse
from sqlalchemy import text
from sqlalchemy.exc import OperationalError
from sqlalchemy.orm import Session

from app import services
from app.auth import require_user
from app.database import get_session
from app.schemas import MeetingCreate, MeetingRead

app = FastAPI(title="Spry API", version="1.0.0")
app.add_middleware(
    CORSMiddleware,
    allow_origins=os.getenv("CORS_ORIGINS", "http://localhost:5173").split(","),
    allow_methods=["GET", "POST"],
    allow_headers=["Authorization", "Content-Type"],
)


@app.exception_handler(OperationalError)
def database_unavailable(_request, _error):
    return JSONResponse(status_code=503, content={"detail": "Database temporarily unavailable"})


@app.get("/health")
def health(session: Session = Depends(get_session)):
    session.execute(text("SELECT 1"))
    return {"status": "ok"}


@app.get("/api/meetings", response_model=list[MeetingRead], dependencies=[Depends(require_user)])
def meetings(session: Session = Depends(get_session)):
    return services.list_meetings(session)


@app.post(
    "/api/meetings",
    response_model=MeetingRead,
    status_code=201,
    dependencies=[Depends(require_user)],
)
def add_meeting(data: MeetingCreate, session: Session = Depends(get_session)):
    return services.create_meeting(session, data)
