import { lazy, Suspense, type ComponentType } from 'react'
import { Routes, Route, Navigate } from 'react-router-dom'
import { ROUTES } from '@/constants/routes'
import { RootLayout, AuthLayout } from '@/layouts'
import { ProtectedRoute } from '@/components/auth'
import PageSkeleton from '@/components/common/PageSkeleton'

const Login = lazy(() => import('@/pages/Login'))
const Dashboard = lazy(() => import('@/pages/Dashboard'))
const Monitoring = lazy(() => import('@/pages/Monitoring'))
const Regions = lazy(() => import('@/pages/Regions'))

function LazyRoute({ element: Component }: { element: ComponentType<unknown> }) {
  return (
    <Suspense fallback={<PageSkeleton />}>
      <Component />
    </Suspense>
  )
}

function ProtectedLazyRoute({ element: Component, roles }: { element: ComponentType<unknown>; roles?: string[] }) {
  return (
    <ProtectedRoute requiredRole={roles}>
      <LazyRoute element={Component} />
    </ProtectedRoute>
  )
}

function AuthLazyRoute({ element: Component }: { element: ComponentType<unknown> }) {
  return (
    <ProtectedRoute requireAuth={false}>
      <LazyRoute element={Component} />
    </ProtectedRoute>
  )
}

export default function AppRoutes() {
  return (
    <Routes>
      <Route path="/" element={<Navigate to={ROUTES.DASHBOARD} replace />} />

      <Route element={<AuthLayout />}>
        <Route path={ROUTES.LOGIN} element={<AuthLazyRoute element={Login} />} />
      </Route>

      <Route element={<RootLayout />}>
        <Route path={ROUTES.DASHBOARD} element={<ProtectedLazyRoute element={Dashboard} />} />
        <Route path={ROUTES.MONITORING} element={<ProtectedLazyRoute element={Monitoring} roles={['admin', 'manager']} />} />
        <Route path={ROUTES.REGIONS} element={<ProtectedLazyRoute element={Regions} roles={['admin', 'manager']} />} />
      </Route>

      <Route path="*" element={<Navigate to={ROUTES.DASHBOARD} replace />} />
    </Routes>
  )
}
