# Proxy SHOP DHP License Server

This is a small demo license server with an admin dashboard.

## Security

Do **not** put the admin username/password in the iOS app or a public GitHub repository. Set them as server environment variables.

```bash
export ADMIN_USERNAME='your-admin'
export ADMIN_PASSWORD='use-a-strong-password'
node server.js
```

Open `/` for the admin dashboard. The iOS app only needs the API base URL, for example `https://your-domain.example/api`.

## Endpoints

- `POST /api/admin/login`
- `POST /api/admin/keys`
- `GET /api/admin/keys`
- `POST /api/license/activate`

Keys use the requested `DHP-IPA-XXXXXX` uppercase/alphanumeric format. Each key has a configurable `maxDevices`, so one key can be limited to one device or deliberately created for multiple devices by an administrator.
