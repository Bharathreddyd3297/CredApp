# CREDPAY Frontend

Premium fintech web client for CREDPAY — built with **React + Vite + Material UI**,
dark luxury theme, glassmorphism, and a mobile-first responsive layout.

## Tech stack

- React 18 + Vite
- React Router DOM (routing)
- Axios (API calls)
- Material UI (MUI) v6 + Emotion (design system / styling)

## Folder structure

```
frontend-react/
├── index.html
├── package.json
├── vite.config.js
├── .env.example
└── src/
    ├── assets/
    ├── components/
    │   ├── Navbar.jsx
    │   ├── Sidebar.jsx
    │   ├── CardTile.jsx
    │   ├── ProtectedRoute.jsx
    │   ├── LoadingSpinner.jsx
    │   └── Footer.jsx
    ├── pages/
    │   ├── LoginPage.jsx
    │   ├── RegisterPage.jsx
    │   ├── DashboardPage.jsx
    │   ├── AddCardPage.jsx
    │   ├── PayBillPage.jsx
    │   ├── PaymentHistoryPage.jsx
    │   ├── SuccessPage.jsx
    │   └── _AuthBranding.jsx   (shared brand panel for login/register)
    ├── services/
    │   └── api.js
    ├── routes/
    │   └── AppRoutes.jsx
    ├── theme/
    │   └── theme.js
    ├── App.jsx
    ├── main.jsx
    └── index.css
```

## Install dependencies

```powershell
cd frontend-react
npm install
```

## Run locally

```powershell
npm run dev
```

App: **http://localhost:5173** (opens automatically).

## Backend configuration

The app talks to two backends (defaults shown). Override by copying
`.env.example` to `.env`:

| Service | Default URL |
|---|---|
| User Service (Spring Boot) | `http://localhost:8080` |
| Payment Service (FastAPI) | `http://localhost:8000` |

## Routes

| Path | Page | Access |
|---|---|---|
| `/login` | Login | Public |
| `/register` | Register | Public |
| `/dashboard` | Dashboard | Protected |
| `/add-card` | Add Card | Protected |
| `/pay-bill` | Pay Bill | Protected |
| `/payment-history` | Payment History | Protected |
| `/success` | Payment Success | Protected |

Protected routes redirect to `/login` when no session is present. On successful
login the app stores `userId`, `fullName`, and `email` in `localStorage`.

> **Note:** Pages gracefully fall back to elegant mock data when the backend is
> unreachable, so the UI is always demo-ready. Real data is used whenever the
> APIs respond.

## Production build

```powershell
npm run build      # outputs to dist/
npm run preview    # preview the production build
```
