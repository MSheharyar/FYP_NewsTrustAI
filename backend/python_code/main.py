from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from routes.verify import router as verify_router
from routes.links import router as links_router
from routes.trending import router as trending_router
from routes.debug import router as debug_router

app = FastAPI(title="NewsTrustAI Backend", version="3.0")

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

app.include_router(verify_router)
app.include_router(links_router)
app.include_router(trending_router)
app.include_router(debug_router)