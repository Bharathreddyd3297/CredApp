import { useState } from 'react';
import { useNavigate, useLocation, Link as RouterLink } from 'react-router-dom';
import {
  Box,
  Paper,
  Typography,
  TextField,
  Button,
  Alert,
  InputAdornment,
  IconButton,
  Link,
  Stack,
} from '@mui/material';
import Visibility from '@mui/icons-material/Visibility';
import VisibilityOff from '@mui/icons-material/VisibilityOff';
import MailOutlineIcon from '@mui/icons-material/MailOutline';
import LockOutlinedIcon from '@mui/icons-material/LockOutlined';

import { loginUser, auth, extractErrorMessage } from '../services/api';
import { glassCard, goldGradient } from '../theme/theme';
import AuthBranding from './_AuthBranding';

export default function LoginPage() {
  const navigate = useNavigate();
  const location = useLocation();
  const redirectTo = location.state?.from?.pathname || '/dashboard';

  const [form, setForm] = useState({ email: '', password: '' });
  const [showPassword, setShowPassword] = useState(false);
  const [error, setError] = useState('');
  const [loading, setLoading] = useState(false);

  const handleChange = (e) => setForm((f) => ({ ...f, [e.target.name]: e.target.value }));

  const handleSubmit = async (e) => {
    e.preventDefault();
    setError('');
    setLoading(true);
    try {
      const data = await loginUser(form);
      auth.save({ userId: data.userId, fullName: data.fullName, email: data.email });
      navigate(redirectTo, { replace: true });
    } catch (err) {
      setError(extractErrorMessage(err, 'Invalid email or password.'));
    } finally {
      setLoading(false);
    }
  };

  return (
    <Box sx={{ minHeight: '100vh', display: 'flex' }}>
      <AuthBranding
        heading="Pay credit card bill for exciting offers"
        subheading="Manage premium cards and pay bills with a seamless, secure experience."
      />

      <Box
        sx={{
          flex: 1,
          display: 'flex',
          alignItems: 'center',
          justifyContent: 'center',
          p: { xs: 2.5, sm: 4 },
        }}
      >
        <Paper
          component="form"
          onSubmit={handleSubmit}
          elevation={0}
          sx={{
            ...glassCard,
            width: '100%',
            maxWidth: 440,
            p: { xs: 3, sm: 4.5 },
            animation: 'fadeInUp .5s ease both',
          }}
        >
          <Typography variant="h4" sx={{ mb: 0.5 }}>
            Welcome back
          </Typography>
          <Typography color="text.secondary" sx={{ mb: 3 }}>
            Sign in to your CREDPAY account
          </Typography>

          {location.state?.registered && !error && (
            <Alert severity="success" sx={{ mb: 2, borderRadius: 2 }}>
              Account created successfully. Please sign in.
            </Alert>
          )}

          {error && (
            <Alert severity="error" sx={{ mb: 2, borderRadius: 2 }}>
              {error}
            </Alert>
          )}

          <Stack spacing={2.2}>
            <TextField
              label="Email"
              name="email"
              type="email"
              value={form.email}
              onChange={handleChange}
              required
              autoComplete="email"
              InputProps={{
                startAdornment: (
                  <InputAdornment position="start">
                    <MailOutlineIcon fontSize="small" />
                  </InputAdornment>
                ),
              }}
            />
            <TextField
              label="Password"
              name="password"
              type={showPassword ? 'text' : 'password'}
              value={form.password}
              onChange={handleChange}
              required
              autoComplete="current-password"
              InputProps={{
                startAdornment: (
                  <InputAdornment position="start">
                    <LockOutlinedIcon fontSize="small" />
                  </InputAdornment>
                ),
                endAdornment: (
                  <InputAdornment position="end">
                    <IconButton onClick={() => setShowPassword((s) => !s)} edge="end" size="small">
                      {showPassword ? <VisibilityOff /> : <Visibility />}
                    </IconButton>
                  </InputAdornment>
                ),
              }}
            />

            <Button type="submit" variant="contained" size="large" disabled={loading} sx={{ mt: 1 }}>
              {loading ? 'Signing in…' : 'Sign In'}
            </Button>
          </Stack>

          <Typography variant="body2" color="text.secondary" sx={{ mt: 3, textAlign: 'center' }}>
            New to CREDPAY?{' '}
            <Link
              component={RouterLink}
              to="/register"
              underline="none"
              sx={{
                fontWeight: 700,
                background: goldGradient,
                WebkitBackgroundClip: 'text',
                WebkitTextFillColor: 'transparent',
              }}
            >
              Create an account
            </Link>
          </Typography>
        </Paper>
      </Box>
    </Box>
  );
}
