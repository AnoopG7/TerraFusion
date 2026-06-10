import { Link } from 'react-router-dom'
import { SITE_CONFIG } from '@/constants/site-config'
import { ROUTES } from '@/constants/routes'
import { Mail, Phone, MapPin } from 'lucide-react'

export default function Footer() {
  return (
    <footer className="border-t bg-card">
      <div className="container mx-auto px-4 py-12">
        <div className="grid gap-8 md:grid-cols-2 lg:grid-cols-3">
          <div>
            <h3 className="mb-4 text-lg font-bold">
              <span className="bg-gradient-to-r from-emerald-400 to-cyan-400 bg-clip-text text-transparent">Terra</span>
              Fusion
            </h3>
            <p className="mb-4 text-sm leading-relaxed text-muted-foreground">
              Advanced climate engineering platform for monitoring and coordinating large-scale environmental initiatives.
            </p>
          </div>

          <div>
            <h4 className="mb-4 text-sm font-semibold text-foreground">Platform</h4>
            <ul className="space-y-2.5">
              <li><Link to={ROUTES.DASHBOARD} className="text-sm text-muted-foreground transition-colors hover:text-foreground">Dashboard</Link></li>
              <li><Link to={ROUTES.MONITORING} className="text-sm text-muted-foreground transition-colors hover:text-foreground">Monitoring</Link></li>
              <li><Link to={ROUTES.REGIONS} className="text-sm text-muted-foreground transition-colors hover:text-foreground">Climate Zones</Link></li>
            </ul>
          </div>

          <div>
            <h4 className="mb-4 text-sm font-semibold text-foreground">Contact</h4>
            <div className="mb-4 space-y-2 text-sm text-muted-foreground">
              <div className="flex items-start gap-2"><Mail className="mt-0.5 h-4 w-4 shrink-0" /><span>{SITE_CONFIG.contact.email}</span></div>
              <div className="flex items-start gap-2"><Phone className="mt-0.5 h-4 w-4 shrink-0" /><span>{SITE_CONFIG.contact.phone}</span></div>
              <div className="flex items-start gap-2"><MapPin className="mt-0.5 h-4 w-4 shrink-0" /><span>{SITE_CONFIG.contact.address}</span></div>
            </div>
          </div>
        </div>

        <div className="mt-10 border-t pt-6">
          <div className="flex flex-col items-center justify-between gap-4 text-sm text-muted-foreground md:flex-row">
            <p>&copy; {new Date().getFullYear()} TerraFusion Environmental Systems. All rights reserved.</p>
          </div>
        </div>
      </div>
    </footer>
  )
}
