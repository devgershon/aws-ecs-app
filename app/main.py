"""
Portfolio API — FastAPI application
Containerised and deployed on AWS ECS Fargate.

Endpoints:
  GET  /          — app info and status
  GET  /health    — ALB health check (must return 200)
  GET  /posts     — fetches published blog posts from the Project 2 Lambda API
  GET  /docs      — auto-generated Swagger UI (free from FastAPI)
"""

import os
import logging
from contextlib import asynccontextmanager

import httpx
from fastapi import FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse

# ── Logger ────────────────────────────────────────────────────────────────────
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# ── Config ────────────────────────────────────────────────────────────────────
# Injected as environment variables by ECS task definition (via Terraform)
BLOG_API_URL   = os.environ.get("BLOG_API_URL", "https://t0tn9g17b7.execute-api.eu-west-2.amazonaws.com")
ALLOWED_ORIGIN = os.environ.get("ALLOWED_ORIGIN", "https://d2eeybsp9y6gvd.cloudfront.net")
APP_VERSION    = os.environ.get("APP_VERSION", "1.0.0")
ENVIRONMENT    = os.environ.get("ENVIRONMENT", "prod")

# ── HTTP client ───────────────────────────────────────────────────────────────
# httpx is an async HTTP client — better than requests for FastAPI's async model.
# We create one shared client at startup and close it on shutdown.
http_client: httpx.AsyncClient | None = None


@asynccontextmanager
async def lifespan(app: FastAPI):
    """Manage the lifecycle of the shared HTTP client."""
    global http_client
    http_client = httpx.AsyncClient(timeout=10.0)
    logger.info("HTTP client initialised")
    yield
    await http_client.aclose()
    logger.info("HTTP client closed")


# ── App ───────────────────────────────────────────────────────────────────────
app = FastAPI(
    title       = "Gershon's Portfolio API",
    description = """
A containerised FastAPI service deployed on AWS ECS Fargate.
Part of a series of AWS cloud engineering projects.

**Live projects:**
- [Static Site](https://d2eeybsp9y6gvd.cloudfront.net) — S3 + CloudFront
- [Blog API](https://t0tn9g17b7.execute-api.eu-west-2.amazonaws.com/posts) — Lambda + DynamoDB
- **This service** — ECS Fargate + ALB
    """,
    version     = APP_VERSION,
    lifespan    = lifespan,
)

# CORS — allow the portfolio site to call this service from the browser
app.add_middleware(
    CORSMiddleware,
    allow_origins  = [ALLOWED_ORIGIN, "http://localhost:3000"],
    allow_methods  = ["GET"],
    allow_headers  = ["*"],
)


# ── Routes ────────────────────────────────────────────────────────────────────

@app.get("/", summary="App info", tags=["General"])
async def root():
    """
    Returns basic information about the service.
    Useful for verifying the container is running correctly.
    """
    return {
        "service":     "Portfolio API",
        "version":     APP_VERSION,
        "environment": ENVIRONMENT,
        "status":      "running",
        "author":      "Gershon Normenyo",
        "github":      "https://github.com/devgershon",
        "projects": {
            "static_site": "https://d2eeybsp9y6gvd.cloudfront.net",
            "blog_api":    f"{BLOG_API_URL}/posts",
            "this_service": "ECS Fargate + ALB",
        },
    }


@app.get("/health", summary="Health check", tags=["General"])
async def health():
    """
    Health check endpoint required by the ALB.
    The ALB calls this every 30 seconds. If it returns anything other
    than 200, the ALB stops sending traffic to this container and ECS
    replaces it with a healthy one.
    """
    return {"status": "healthy", "version": APP_VERSION}


@app.get("/posts", summary="Get blog posts", tags=["Blog"])
async def get_posts(status: str = "published"):
    """
    Fetches blog posts from the serverless Lambda API (Project 2).

    This demonstrates service-to-service communication —
    a containerised app calling a serverless API.

    - **status**: filter by post status (published | draft). Defaults to published.
    """
    if not http_client:
        raise HTTPException(status_code=503, detail="HTTP client not initialised")

    try:
        url = f"{BLOG_API_URL}/posts"
        logger.info("Fetching posts from %s", url)

        response = await http_client.get(url, params={"status": status})
        response.raise_for_status()

        data = response.json()
        posts = data.get("posts", [])

        return {
            "source":   "Lambda API (Project 2)",
            "count":    len(posts),
            "posts":    posts,
        }

    except httpx.TimeoutException:
        logger.error("Timeout fetching posts from Lambda API")
        raise HTTPException(status_code=504, detail="Blog API timed out")

    except httpx.HTTPStatusError as e:
        logger.error("Blog API returned %s", e.response.status_code)
        raise HTTPException(
            status_code=e.response.status_code,
            detail=f"Blog API error: {e.response.text}"
        )

    except Exception as e:
        logger.exception("Unexpected error fetching posts: %s", e)
        raise HTTPException(status_code=500, detail="Internal server error")


@app.get("/posts/{post_id}", summary="Get a single post", tags=["Blog"])
async def get_post(post_id: str):
    """
    Fetches a single blog post by ID from the Lambda API (Project 2).
    """
    if not http_client:
        raise HTTPException(status_code=503, detail="HTTP client not initialised")

    try:
        url = f"{BLOG_API_URL}/posts/{post_id}"
        logger.info("Fetching post %s from %s", post_id, url)

        response = await http_client.get(url)

        if response.status_code == 404:
            raise HTTPException(status_code=404, detail=f"Post {post_id} not found")

        response.raise_for_status()
        return response.json()

    except HTTPException:
        raise

    except Exception as e:
        logger.exception("Unexpected error fetching post %s: %s", post_id, e)
        raise HTTPException(status_code=500, detail="Internal server error")
