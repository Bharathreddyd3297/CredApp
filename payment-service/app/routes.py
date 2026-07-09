"""API routes for the payment service."""

from fastapi import APIRouter, Depends
from sqlalchemy.orm import Session

from app.database import get_db
from app.schemas import PaymentHistoryItem, PaymentRequest, PaymentResponse
from app.services import create_payment, get_payment_history

router = APIRouter(prefix="/api/payment", tags=["payment"])


# Used by the pipeline's post-deployment smoke test (GET /api/payment/health).
# Kept separate from the root /health used by the liveness/readiness probes.
@router.get("/health")
def health():
    return {"status": "UP"}


@router.post("/pay", response_model=PaymentResponse)
def pay(request: PaymentRequest, db: Session = Depends(get_db)) -> PaymentResponse:
    return create_payment(db, request)


@router.get("/history/{user_id}", response_model=list[PaymentHistoryItem])
def history(user_id: int, db: Session = Depends(get_db)) -> list[PaymentHistoryItem]:
    return get_payment_history(db, user_id)
