"""CREDPAY Payment Service - FastAPI application entry point.

Run with:
    uvicorn app.main:app --reload --port 8000
"""

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from app.routes import router

app = FastAPI(
    title="CREDPAY Payment Service",
    description="Simulated payments backed by the existing credpay PostgreSQL database.",
    version="0.1.0",
)

# Allow the React dev frontend (Vite) to call this service from the browser.
app.add_middleware(
    CORSMiddleware,
    allow_origins=["http://localhost:5173", "http://127.0.0.1:5173"],
    allow_methods=["*"],
    allow_headers=["*"],
    allow_credentials=True,
)

app.include_router(router)


@app.get("/health", tags=["health"])
def health():
    return {"status": "UP"}
