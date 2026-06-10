import { useEffect, useState } from 'react'
import { motion } from 'framer-motion'
import { Download, Filter } from 'lucide-react'
import { PageMeta } from '@/components/common'
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card'
import { Button } from '@/components/ui/button'
import { Badge } from '@/components/ui/badge'
import { Tabs, TabsContent, TabsList, TabsTrigger } from '@/components/ui/tabs'
import { api } from '@/lib/api'

interface SensorReading {
  id: string
  sensorId: string
  sensorType: string
  co2Ppm: number
  temperatureC: number
  status: string
  region: string
}

export default function Reports() {
  const [readings, setReadings] = useState<SensorReading[]>([])

  useEffect(() => {
    api.getSensorReport().then(setReadings)
  }, [])

  const totals = {
    normal: readings.filter((r) => r.status === 'normal').length,
    anomaly: readings.filter((r) => r.status === 'anomaly').length,
    critical: readings.filter((r) => r.status === 'critical').length,
    avgCo2: readings.length > 0 ? readings.reduce((sum, r) => sum + r.co2Ppm, 0) / readings.length : 0,
  }

  return (
    <>
      <PageMeta title="Reports & Analytics — TerraFusion" />
      <div className="space-y-6">
        <div className="flex items-center justify-between">
          <div>
            <h1 className="text-3xl font-bold tracking-tight">Environmental Reports</h1>
            <p className="text-muted-foreground">Data-driven insights across all climate monitoring operations</p>
          </div>
          <div className="flex gap-2">
            <Button variant="outline" size="sm" disabled><Filter className="mr-2 h-4 w-4" /> Filter</Button>
            <Button variant="outline" size="sm" disabled><Download className="mr-2 h-4 w-4" /> Export</Button>
          </div>
        </div>

        <motion.div initial={{ opacity: 0, y: 20 }} animate={{ opacity: 1, y: 0 }} className="grid gap-4 md:grid-cols-4">
          <Card><CardHeader className="pb-2"><CardTitle className="text-sm text-muted-foreground">Avg CO₂</CardTitle></CardHeader><CardContent><p className="text-2xl font-bold">{totals.avgCo2.toFixed(1)} ppm</p></CardContent></Card>
          <Card><CardHeader className="pb-2"><CardTitle className="text-sm text-muted-foreground">Normal</CardTitle></CardHeader><CardContent><p className="text-2xl font-bold text-emerald-500">{totals.normal}</p></CardContent></Card>
          <Card><CardHeader className="pb-2"><CardTitle className="text-sm text-muted-foreground">Anomalies</CardTitle></CardHeader><CardContent><p className="text-2xl font-bold text-yellow-500">{totals.anomaly}</p></CardContent></Card>
          <Card><CardHeader className="pb-2"><CardTitle className="text-sm text-muted-foreground">Critical</CardTitle></CardHeader><CardContent><p className="text-2xl font-bold text-red-500">{totals.critical}</p></CardContent></Card>
        </motion.div>

        <Tabs defaultValue="readings">
          <TabsList>
            <TabsTrigger value="readings">Sensor Readings</TabsTrigger>
            <TabsTrigger value="activity">Activity Log</TabsTrigger>
            <TabsTrigger value="health">System Health</TabsTrigger>
          </TabsList>

          <TabsContent value="readings" className="mt-4">
            <Card>
              <CardHeader><CardTitle>Sensor Reading History</CardTitle></CardHeader>
              <CardContent>
                <div className="rounded-lg border">
                  <table className="w-full text-sm">
                    <thead>
                      <tr className="border-b bg-muted/50">
                        <th className="px-4 py-3 text-left font-medium">ID</th>
                        <th className="px-4 py-3 text-left font-medium">Sensor</th>
                        <th className="px-4 py-3 text-left font-medium">Type</th>
                        <th className="px-4 py-3 text-left font-medium">CO₂ (ppm)</th>
                        <th className="px-4 py-3 text-left font-medium">Zone</th>
                        <th className="px-4 py-3 text-left font-medium">Status</th>
                      </tr>
                    </thead>
                    <tbody>
                      {readings.slice(0, 15).map((r) => (
                        <tr key={r.id} className="border-b transition-colors hover:bg-muted/30">
                          <td className="px-4 py-3 font-mono text-xs">{r.id}</td>
                          <td className="px-4 py-3">{r.sensorId}</td>
                          <td className="px-4 py-3 capitalize">{r.sensorType}</td>
                          <td className="px-4 py-3 font-medium">{r.co2Ppm.toFixed(1)}</td>
                          <td className="px-4 py-3 text-xs">{r.region}</td>
                          <td className="px-4 py-3">
                            <Badge variant={r.status === 'normal' ? 'default' : r.status === 'anomaly' ? 'secondary' : 'destructive'} className="capitalize">
                              {r.status}
                            </Badge>
                          </td>
                        </tr>
                      ))}
                    </tbody>
                  </table>
                </div>
              </CardContent>
            </Card>
          </TabsContent>

          <TabsContent value="activity" className="mt-4">
            <Card><CardHeader><CardTitle>Environmental Activity Log</CardTitle></CardHeader><CardContent><p className="text-sm text-muted-foreground">Activity tracking and audit trail for all platform operations. Select a date range to filter.</p></CardContent></Card>
          </TabsContent>

          <TabsContent value="health" className="mt-4">
            <Card><CardHeader><CardTitle>System Health Report</CardTitle></CardHeader><CardContent><p className="text-sm text-muted-foreground">Historical system health metrics and performance trends across all climate zones.</p></CardContent></Card>
          </TabsContent>
        </Tabs>
      </div>
    </>
  )
}
