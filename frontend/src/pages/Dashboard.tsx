import { useEffect, useState } from 'react'
import { motion } from 'framer-motion'
import { Activity, Thermometer, CheckCircle2, Clock, CloudSun, TrendingUp, Satellite, Factory } from 'lucide-react'
import { PageMeta, StatCard } from '@/components/common'
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card'
import { Badge } from '@/components/ui/badge'
import { api } from '@/lib/api'
import { useAuthStore } from '@/store'

interface KPI {
  totalReadings: number
  dataAccuracy: number
  activeSensors: number
  readingsToday: number
  systemUptime: number
  avgLatency: number
  carbonCaptured: number
  activeZones: number
}

interface SensorReading {
  id: string
  sensorId: string
  sensorType: string
  co2Ppm: number
  temperatureC: number
  status: string
  region: string
}

interface SystemMetrics {
  cpu: number
  memory: number
  disk: number
  networkIn: number
  networkOut: number
  dbConnections: number
  requestsPerMin: number
}

export default function Dashboard() {
  const { user } = useAuthStore()
  const [kpi, setKpi] = useState<KPI | null>(null)
  const [readings, setReadings] = useState<SensorReading[]>([])
  const [metrics, setMetrics] = useState<SystemMetrics | null>(null)

  useEffect(() => {
    api.getKPIs().then(setKpi)
    api.getRecentReadings(8).then(setReadings)
    api.getSystemMetrics().then(setMetrics)
  }, [])

  const statCards = kpi ? [
    { title: 'Total Readings', value: kpi.totalReadings.toLocaleString(), icon: Activity, change: '+12.5%', changeType: 'up' as const },
    { title: 'Data Accuracy', value: `${kpi.dataAccuracy}%`, icon: TrendingUp, change: '+0.8%', changeType: 'up' as const },
    { title: 'Active Sensors', value: kpi.activeSensors.toString(), icon: Thermometer, change: '+5.2%', changeType: 'up' as const },
    { title: 'Avg CO₂', value: `${kpi.carbonCaptured} ppm`, icon: CloudSun, change: '+2.3 ppm', changeType: 'up' as const },
    { title: 'System Uptime', value: `${kpi.systemUptime}%`, icon: CheckCircle2, change: '99.9% SLA', changeType: 'up' as const },
    { title: 'Avg Latency', value: `${kpi.avgLatency}ms`, icon: Clock, change: '-15ms', changeType: 'up' as const },
  ] : []

  return (
    <>
      <PageMeta title="Dashboard — TerraFusion" />
      <div className="space-y-6">
        <div className="flex items-center justify-between">
          <div>
            <h1 className="text-3xl font-bold tracking-tight">Climate Operations Dashboard</h1>
            <p className="text-muted-foreground">
              Welcome back, {user?.firstName} · {user?.region}
            </p>
          </div>
          <Badge variant="outline" className="capitalize text-sm px-3 py-1.5">
            {user?.role} Access
          </Badge>
        </div>

        <motion.div
          initial={{ opacity: 0, y: 20 }}
          animate={{ opacity: 1, y: 0 }}
          className="grid gap-4 md:grid-cols-2 lg:grid-cols-3 xl:grid-cols-6"
        >
          {statCards.map((stat) => (
            <StatCard key={stat.title} {...stat} />
          ))}
        </motion.div>

        <div className="grid gap-6 lg:grid-cols-2">
          <Card>
            <CardHeader>
              <CardTitle className="text-lg">Environmental Health</CardTitle>
            </CardHeader>
            <CardContent>
              <div className="space-y-5">
                {[
                  { label: 'Sensor Network', value: 94, icon: Satellite, sub: `${kpi?.activeSensors || 0} of ${(kpi?.activeSensors || 0) + 3} online` },
                  { label: 'Data Pipeline', value: 97, icon: Activity, sub: `${metrics?.requestsPerMin.toLocaleString() || 0} readings/min` },
                  { label: 'Climate Models', value: kpi ? Math.round(kpi.dataAccuracy) : 98, icon: CloudSun, sub: `${kpi?.dataAccuracy || 0}% prediction accuracy` },
                  { label: 'Carbon Capture', value: 88, icon: Factory, sub: '3 of 4 facilities operational' },
                ].map((m) => (
                  <div key={m.label}>
                    <div className="mb-1.5 flex items-center justify-between text-sm">
                      <div className="flex items-center gap-2">
                        <m.icon className="h-4 w-4 text-muted-foreground" />
                        <span>{m.label}</span>
                      </div>
                      <span className="font-medium">{m.value}%</span>
                    </div>
                    <div className="h-2 overflow-hidden rounded-full bg-muted">
                      <div className={`h-full rounded-full transition-all duration-500 ${m.value > 85 ? 'bg-emerald-500' : m.value > 70 ? 'bg-yellow-500' : 'bg-red-500'}`} style={{ width: `${m.value}%` }} />
                    </div>
                    <p className="mt-0.5 text-xs text-muted-foreground">{m.sub}</p>
                  </div>
                ))}
              </div>
            </CardContent>
          </Card>

          <Card>
            <CardHeader>
              <CardTitle className="text-lg">Recent Sensor Readings</CardTitle>
            </CardHeader>
            <CardContent>
              <div className="space-y-3">
                {readings.slice(0, 6).map((r) => (
                  <div key={r.id} className="flex items-center justify-between rounded-lg border p-3 text-sm">
                    <div className="min-w-0 flex-1">
                      <p className="truncate font-medium">{r.sensorId} · {r.sensorType}</p>
                      <p className="text-xs text-muted-foreground">{r.id} · {r.region}</p>
                    </div>
                    <div className="ml-4 text-right">
                      <p className="font-medium">{r.co2Ppm} ppm</p>
                      <Badge variant={r.status === 'normal' ? 'default' : r.status === 'anomaly' ? 'secondary' : 'destructive'} className="text-xs capitalize">
                        {r.status}
                      </Badge>
                    </div>
                  </div>
                ))}
              </div>
            </CardContent>
          </Card>
        </div>
      </div>
    </>
  )
}
