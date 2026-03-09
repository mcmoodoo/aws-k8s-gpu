## Cursor CLI Session Token Quick Guide

A concise guide to find your Cursor CLI (`cursor-agent`) session token via browser inspection.

---

## Step 1 — Log in via Browser

```bash
cursor-agent login
```

Opens your browser to authenticate with your Cursor account.

---

## Step 2 — Open DevTools

- Press **F12** or **Ctrl+Shift+I** (Cmd+Option+I on macOS).
- Go to the **Network** tab.

---

## Step 3 — Capture a Request

- Perform an action in Cursor that triggers a network request.
- Look for requests to:

```text
https://www.cursor.com/api/...
https://api.cursor.com/...
```

---

## Step 4 — Inspect Request Headers

- Select a request → **Headers → Request Headers**.
- Look for a cookie:

```text
WorkosCursorSessionToken=<long_token>
```

---

## Step 5 — Copy the Token

- The value of `WorkosCursorSessionToken` is your session token.
- This token is automatically used by `cursor-agent` for requests.

---

### Notes

- CLI requests likely send the same token automatically.
- The token is **not** in `Authorization: Bearer`.
- Keep the token secure; it grants access to your subscription.

