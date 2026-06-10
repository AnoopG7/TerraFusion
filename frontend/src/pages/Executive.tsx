import { useEffect, useState } from 'react'
import { motion } from 'framer-motion'
import { TrendingUp, Activity, Thermometer, Globe, CloudSun } from 'lucide-react'
import { PageMeta } from '@/components/common'
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card'
import { Badge } from '@/components/ui/badge'
import { Tabs, TabsContent, TabsList, TabsTrigger } from '@/components/ui/tabs'
import { api } from '@/lib/api'

interface KPI {
  totalReadings: number
  dataAccuracy: number
  activeSensors: number
  systemUptime: number
  readingsToday: number
  activeZones: number
}

export default function Executive() {
  const [kpi, setKpi] = useState<KPI | null>(null)

  useEffect(() => {
    api.getKPIs().then(setKpi)
  }, [])

  const zoneData = kpi ? [
    { zone: 'North Atlantic', readings: Math.round(kpi.totalReadings * 0.42), sensors: 24, growth: 12.3, health: 'healthy' as const },
    { zone: 'Pacific Northwest', readings: Math.round(kpi.totalReadings * 0.28), sensors: 18, growth: 8.7, health: 'healthy' as const },
    { zone: 'European Climate', readings: Math.round(kpi.totalReadings * 0.18), sensors: 15, growth: 15.2, health: 'healthy' as const },
    { zone: 'Asia Pacific Basin', readings: Math.round(kpi.totalReadings * 0.12), sensors: 10, growth: 22.1, health: 'degraded' as const },
  ] : []

  return (
    <>
      <PageMeta title="Executive Portal — TerraFusion" />
      <div className="space-y-6">
        <div className="flex items-center justify-between">
          <div>
            <h1 className="text-3xl font-bold tracking-tight">Executive Portal</h1>
            <p className="text-muted-foreground">Aggregated environmental insights for leadership</p>
          </div>
          <Badge variant="outline" className="text-sm px-3 py-1.5">
            {new Date().toLocaleDateString('en-US', { weekday: 'long', year: 'numeric', month: 'long', day: 'numeric' })}
          </Badge>
        </div>

        {kpi && (
          <>
            <motion.div initial={{ opacity: 0, y: 20 }} animate={{ opacity: 1, y: 0 }} className="grid gap-4 md:grid-cols-2 lg:grid-cols-4">
              <Card className="bg-gradient-to-br from-emerald-500/10 to-cyan-500/5 border-emerald-500/20">
                <CardHeader className="pb-2"><CardTitle className="text-sm text-muted-foreground">Readings Today</CardTitle></CardHeader>
                <CardContent><p className="text-3xl font-bold">{kpi.readingsToday.toLocaleString()}</p><p className="flex items-center gap-1 text-xs text-emerald-500"><TrendingUp className="h-3 w-3" /> +12.3% vs last week</p></CardContent>
              </Card>
              <Card>
                <CardHeader className="pb-2"><CardTitle className="text-sm text-muted-foreground">Total Readings</CardTitle></CardHeader>
                <CardContent><p className="text-3xl font-bold">{kpi.totalReadings.toLocaleString()}</p><p className="flex items-center gap-1 text-xs text-emerald-500"><TrendingUp className="h-3 w-3" /> +8.5% MoM</p></CardContent>
              </Card>
              <Card>
                <CardHeader className="pb-2"><CardTitle className="text-sm text-muted-foreground">Active Sensors</CardTitle></CardHeader>
                <CardContent><p className="text-3xl font-bold">{kpi.activeSensors}</p><p className="flex items-center gap-1 text-xs text-emerald-500"><TrendingUp className="h-3 w-3" /> +5.2% MoM</p></CardContent>
              </Card>
              <Card>
                <CardHeader className="pb-2"><CardTitle className="text-sm text-muted-foreground">System Uptime</CardTitle></CardHeader>
                <CardContent><p className="text-3xl font-bold">{kpi.systemUptime}%</p><p className="flex items-center gap-1 text-xs text-emerald-500"><TrendingUp className="h-3 w-3" /> 99.9% SLA met</p></CardContent>
              </Card>
            </motion.div>

            <Tabs defaultValue="overview">
              <TabsList>
                <TabsTrigger value="overview">Overview</TabsTrigger>
                <TabsTrigger value="zones">Zone Performance</TabsTrigger>
                <TabsTrigger value="growth">Growth Metrics</TabsTrigger>
              </TabsList>

              <TabsContent value="overview" className="mt-4">
                <div className="grid gap-6 lg:grid-cols-2">
                  <Card>
                    <CardHeader><CardTitle>Sensor Distribution</CardTitle></CardHeader>
                    <CardContent>
                      <div className="space-y-4">
                        {zoneData.map((z) => (
                          <div key={z.zone}>
                            <div className="mb-1 flex justify-between text-sm">
                              <span>{z.zone}</span>
                              <span className="font-medium">{z.sensors} sensors</span>
                            </div>
                            <div className="h-2 overflow-hidden rounded-full bg-muted">
                              <div className="h-full rounded-full bg-primary" style={{ width: `${(z.sensors / Math.max(...zoneData.map((zd) => zd.sensors))) * 100}%` }} />
                            </div>
                          </div>
                        ))}
                      </div>
                    </CardContent>
                  </Card>
                  <Card>
                    <CardHeader><CardTitle>Key Metrics</CardTitle></CardHeader>
                    <CardContent>
                      <div className="space-y-4">
                        {[
                          { label: 'Data Accuracy', value: `${kpi.dataAccuracy}%`, trend: '+0.8%', icon: Activity },
                          { label: 'Active Zones', value: String(kpi.activeZones), trend: '+1 this quarter', icon: Globe },
                          { label: 'Avg CO₂', value: '418.3 ppm', trend: '+2.3 ppm', icon: CloudSun },
                          { label: 'Sensor Growth', value: '+15.4%', trend: 'MoM increase', icon: Thermometer },
                        ].map((m) => (
                          <div key={m.label} className="flex items-center justify-between rounded-lg border p-3">
                            <div className="flex items-center gap-3">
                              <div className="rounded-md bg-primary/10 p-2"><m.icon className="h-4 w-4 text-primary" /></div>
                              <div><p className="text-sm font-medium">{m.label}</p><p className="text-xs text-muted-foreground">{m.trend}</p></div>
                            </div>
                            <p className="text-lg font-bold">{m.value}</p>
                          </div>
                        ))}
                      </div>
                    </CardContent>
                  </Card>
                </div>
              </TabsContent>

              <TabsContent value="zones" className="mt-4">
                <Card>
                  <CardHeader><CardTitle>Zone Performance</CardTitle></CardHeader>
                  <CardContent>
                    <div className="rounded-lg border">
                      <table className="w-full text-sm">
                        <thead>
                          <tr className="border-b bg-muted/50">
                            <th className="px-4 py-3 text-left font-medium">Zone</th>
                            <th className="px-4 py-3 text-left font-medium">Readings</th>
                            <th className="px-4 py-3 text-left font-medium">Sensors</th>
                            <th className="px-4 py-3 text-left font-medium">Growth</th>
                            <th className="px-4 py-3 text-left font-medium">Health</th>
                          </tr>
                        </thead>
                        <tbody>
                          {zoneData.map((z) => (
                            <tr key={z.zone} className="border-b transition-colors hover:bg-muted/30">
                              <td className="px-4 py-3 font-medium">{z.zone}</td>
                              <td className="px-4 py-3">{z.readings.toLocaleString()}</td>
                              <td className="px-4 py-3">{z.sensors}</td>
                              <td className="px-4 py-3">
                                <span className="flex items-center gap-1 text-emerald-500">
                                  <TrendingUp className="h-3 w-3" /> {z.growth}%
                                </span>
                              </td>
                              <td className="px-4 py-3">
                                <Badge variant="outline" className="capitalize">{z.health}</Badge>
                              </td>
                            </tr>
                          ))}
                        </tbody>
                      </table>
                    </div>
                  </CardContent>
                </Card>
              </TabsContent>

              <TabsContent value="growth" className="mt-4">
                <Card><CardHeader><CardTitle>Growth Metrics</CardTitle></CardHeader><CardContent><p className="text-sm text-muted-foreground">Month-over-month and quarter-over-quarter growth analysis across all metrics. Sensor network is projected to expand 18% next quarter based on current deployment trends.</p></CardContent></Card>
              </TabsContent>
            </Tabs>
          </>
        )}
      </div>
    </>
  )
}
