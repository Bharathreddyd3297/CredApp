import axios from 'axios';

/**
 * Centralized API layer for CREDPAY.
 *
 *  - userApi    -> Spring Boot User Service    (default http://localhost:8080)
 *  - paymentApi -> FastAPI Payment Service     (default http://localhost:8000)
 *
 * Base URLs can be overridden via Vite env vars (see .env.example).
 */

const USER_BASE_URL = import.meta.env.VITE_USER_API_URL || 'http://localhost:8080';
const PAYMENT_BASE_URL = import.meta.env.VITE_PAYMENT_API_URL || 'http://localhost:8000';

export const userApi = axios.create({
  baseURL: USER_BASE_URL,
  headers: { 'Content-Type': 'application/json' },
  timeout: 15000,
});

export const paymentApi = axios.create({
  baseURL: PAYMENT_BASE_URL,
  headers: { 'Content-Type': 'application/json' },
  timeout: 15000,
});

/**
 * Normalize backend errors. Spring returns { message }, FastAPI returns
 * { detail } (string, or an array for 422 validation errors).
 */
export function extractErrorMessage(error, fallback = 'Something went wrong. Please try again.') {
  const data = error?.response?.data;
  if (!data) {
    if (error?.code === 'ECONNABORTED') return 'Request timed out. Is the backend running?';
    if (error?.message === 'Network Error') return 'Cannot reach the server. Is the backend running?';
    return fallback;
  }
  if (typeof data.message === 'string') return data.message;
  if (typeof data.detail === 'string') return data.detail;
  if (Array.isArray(data.detail) && data.detail.length) {
    return data.detail.map((d) => d.msg || JSON.stringify(d)).join(', ');
  }
  return fallback;
}

// --- Auth / session helpers -------------------------------------------
export const auth = {
  save({ userId, fullName, email }) {
    localStorage.setItem('userId', String(userId));
    localStorage.setItem('fullName', fullName ?? '');
    localStorage.setItem('email', email ?? '');
  },
  get() {
    const userId = localStorage.getItem('userId');
    if (!userId) return null;
    return {
      userId: Number(userId),
      fullName: localStorage.getItem('fullName') || '',
      email: localStorage.getItem('email') || '',
    };
  },
  isAuthenticated() {
    return Boolean(localStorage.getItem('userId'));
  },
  clear() {
    localStorage.removeItem('userId');
    localStorage.removeItem('fullName');
    localStorage.removeItem('email');
  },
};

// --- User Service endpoints -------------------------------------------
export async function registerUser({ fullName, email, password }) {
  const { data } = await userApi.post('/api/users/register', { fullName, email, password });
  return data; // { message }
}

export async function loginUser({ email, password }) {
  const { data } = await userApi.post('/api/users/login', { email, password });
  return data; // { userId, fullName, email, message }
}

export async function addCard({ userId, cardHolder, cardNumber, cardNetwork, expiryMonth, expiryYear }) {
  const { data } = await userApi.post('/api/cards/add', {
    userId,
    cardHolder,
    cardNumber,
    cardNetwork,
    expiryMonth,
    expiryYear,
  });
  return data; // { message }
}

export async function listCards(userId) {
  const { data } = await userApi.get(`/api/cards/user/${userId}`);
  return data; // [{ id, cardHolder, cardNumber, cardNetwork }]
}

// --- Payment Service endpoints ----------------------------------------
export async function payBill({ userId, cardId, amount, upiId }) {
  const { data } = await paymentApi.post('/api/payment/pay', { userId, cardId, amount, upiId });
  return data; // { transactionId, status, amount }
}

export async function paymentHistory(userId) {
  const { data } = await paymentApi.get(`/api/payment/history/${userId}`);
  return data; // [{ transactionId, amount, status, createdAt }]
}
