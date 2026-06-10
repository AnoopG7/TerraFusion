import { Router, Request, Response } from 'express'
import db from '../db/connection.js'

const router = Router()

function mapReading(r: any) {
  return {
    id: r.reading_id,
    sensorId: r.sensor_id,
    sensorType: r.sensor_type,
    co2Ppm: Number(r.co2_ppm),
    temperatureC: Number(r.temperature_c),
    humidity: Number(r.humidity),
    region: r.region,
    status: r.status,
    timestamp: r.timestamp,
  }
}

router.get('/', async (_req: Request, res: Response) => {
  try {
    const rows = await db('sensor_readings').orderBy('timestamp', 'desc').limit(100)
    res.json(rows.map(mapReading))
  } catch (err) {
    console.error('Sensor readings error:', err)
    res.status(500).json({ error: 'Server error' })
  }
})

router.get('/report', async (_req: Request, res: Response) => {
  try {
    const rows = await db('sensor_readings').orderBy('timestamp', 'desc')
    res.json(rows.map((r: any) => ({
      id: r.reading_id,
      sensorId: r.sensor_id,
      sensorType: r.sensor_type,
      co2Ppm: Number(r.co2_ppm),
      temperatureC: Number(r.temperature_c),
      status: r.status,
      region: r.region,
    })))
  } catch (err) {
    console.error('Sensor report error:', err)
    res.status(500).json({ error: 'Server error' })
  }
})

export default router
