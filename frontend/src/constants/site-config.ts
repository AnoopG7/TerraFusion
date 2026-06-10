import { ROUTES } from './routes'

export const SITE_CONFIG = {
  name: 'TerraFusion',
  tagline: 'Climate Engineering Platform',
  description:
    'Advanced climate engineering platform for monitoring and coordinating large-scale environmental initiatives.',
  url: 'https://terrafusion.io',
  contact: {
    email: 'ops@terrafusion.io',
    phone: '+1 (555) 789-0123',
    address: '200 Green Technology Park, Suite 400, San Francisco, CA 94105',
  },
  navLinks: [
    { label: 'Dashboard', href: ROUTES.DASHBOARD, roles: ['admin', 'manager', 'staff'] },
    { label: 'Monitoring', href: ROUTES.MONITORING, roles: ['admin', 'manager'] },
    { label: 'Zones', href: ROUTES.REGIONS, roles: ['admin', 'manager'] },
  ],
} as const
