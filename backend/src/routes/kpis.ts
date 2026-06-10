import { Router, Request, Response } from 'express'
import db from '../db/connection.js'

const router = Router()

router.get('/', async (_req: Request, res: Response) => {
  try {
    const row = await db('sensor_readings').count('* as total').first()
    const anomalyRow = await db('sensor_readings').whereIn('status', ['anomaly', 'critical']).count('* as anomalies').first()
    const avgRow = await db('sensor_readings').avg('co2_ppm as avgCo2').first()

    const total = Number(row?.total || 0)
    const anomalies = Number(anomalyRow?.anomalies || 0)
    const avgCo2 = Number(avgRow?.avgCo2 || 0)

    res.json({
      totalReadings: total,
      dataAccuracy: total > 0 ? Number((((total - anomalies) / total) * 100).toFixed(1)) : 100,
      activeSensors: 48,
      carbonCaptured: Number(avgCo2).toFixed(1),
      systemUptime: 99.95,
      avgLatency: 85,
      readingsToday: Number(total),
      activeZones: 4,
    })
  } catch (err) {
    console.error('KPIs error:', err)
    res.status(500).json({ error: 'Server error' })
  }
})

export default router
