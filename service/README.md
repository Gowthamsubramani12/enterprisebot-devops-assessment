# EnterpriseBot Service

A minimal production-ready HTTP service built with **FastAPI** and **Python 3.12**.

---

## Endpoints

| Method | Path      | Description                        |
|--------|-----------|------------------------------------|
| GET    | `/`       | Returns app name, version, pod     |
| GET    | `/healthz` | Liveness probe — returns `200 ok` |

---

## Environment Variables

| Variable   | Default        | Description               |
|------------|----------------|---------------------------|
| `APP_NAME` | `EnterpriseBot` | Application name          |
| `VERSION`  | `0.0.0`        | Application version       |

---

## Build

```bash
docker build -t enterprisebot:1.0.0 .
```

---

## Run

```bash
docker run \
  -e APP_NAME="EnterpriseBot" \
  -e VERSION="1.0.0" \
  -p 8080:8080 \
  enterprisebot:1.0.0
```

---

## Verify

```bash
curl http://localhost:8080/

curl http://localhost:8080/healthz
```

### Expected responses

```json
// GET /
{
  "app": "EnterpriseBot",
  "version": "1.0.0",
  "pod": "<container-hostname>"
}

// GET /healthz
{
  "status": "ok"
}
```
