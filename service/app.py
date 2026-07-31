import os
import socket

from fastapi import FastAPI
from fastapi.responses import JSONResponse

app = FastAPI()


@app.get("/")
def root():
    return JSONResponse(
        content={
            "app": os.getenv("APP_NAME", "EnterpriseBot"),
            "version": os.getenv("VERSION", "0.0.0"),
            "pod": socket.gethostname(),
        }
    )


@app.get("/healthz")
def healthz():
    return JSONResponse(content={"status": "ok"})


if __name__ == "__main__":
    import uvicorn

    uvicorn.run("app:app", host="0.0.0.0", port=8080)
