import { Navigate, useLocation } from 'react-router-dom';
import { auth } from '../services/api';

/**
 * Guards routes that require an authenticated session.
 * Redirects to /login (remembering the attempted location) when no user
 * is present in localStorage.
 */
export default function ProtectedRoute({ children }) {
  const location = useLocation();

  if (!auth.isAuthenticated()) {
    return <Navigate to="/login" replace state={{ from: location }} />;
  }

  return children;
}
